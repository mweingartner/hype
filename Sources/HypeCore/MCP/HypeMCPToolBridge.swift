import Foundation

public enum HypeMCPToolBridge {
    public static let mcpControlToolNames: Set<String> = [
        "hype_get_app_state",
        "hype_list_open_stacks",
        "hype_get_stack_document",
        "hype_get_object",
        "hype_canvas_hit_test",
        "hype_open_script_editor",
        "hype_dispatch_message",
        "hype_get_preferences",
        "hype_set_preference",
        "hype_set_secret",
        "hype_delete_secret",
        "hype_set_script",
        "hype_replace_part",
        "hype_run_existing_tool",
        "hype_preview_transaction",
        "hype_apply_transaction",
        "hype_rollback_transaction",
        "hype_create_test_stack",
        "hype_list_windows",
        "hype_focus_window",
        "hype_wait_for_window",
        "hype_list_menu_commands",
        "hype_trigger_menu_command",
        "hype_get_script_debugger_state",
        "hype_set_script_tracing",
        "hype_clear_script_trace",
        "hype_open_script_trace_source",
        "hype_add_script_breakpoint",
        "hype_remove_script_breakpoint",
        "hype_add_script_watchpoint",
        "hype_remove_script_watchpoint",
        "hype_resume_script_execution",
        "hype_step_into_script_execution",
        "hype_step_over_script_execution",
        "hype_wait_for_debugger_pause",
        "hype_step_script_execution_and_wait",
        "hype_get_script_editor_state",
        "hype_toggle_script_editor_breakpoint"
    ]

    public static var allTools: [HypeMCPTool] {
        HypeToolDefinitions.allTools.map(mcpTool(from:)) + controlTools
    }

    public static func tools(from hypeTools: [OllamaTool]) -> [HypeMCPTool] {
        hypeTools.map(mcpTool(from:)) + controlTools
    }

    public static var controlOnlyTools: [HypeMCPTool] {
        controlTools
    }

    public static func stringArguments(from value: HypeMCPJSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        return object.mapValues(\.flattenedString)
    }

    public static func stringArguments(from arguments: [String: HypeMCPJSONValue]) -> [String: String] {
        arguments.mapValues(\.flattenedString)
    }

    public static func parseArgumentsJSON(_ text: String) -> [String: String] {
        guard let data = text.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(HypeMCPJSONValue.self, from: data) else {
            return [:]
        }
        return stringArguments(from: decoded)
    }

    private static func mcpTool(from tool: OllamaTool) -> HypeMCPTool {
        HypeMCPTool(
            name: tool.function.name,
            description: tool.function.description,
            inputSchema: schema(from: tool.function.parameters)
        )
    }

    private static func schema(from parameters: OllamaParameters) -> HypeMCPJSONValue {
        var properties: [String: HypeMCPJSONValue] = [:]
        for (name, property) in parameters.properties {
            var schema: [String: HypeMCPJSONValue] = [
                "type": .string(property.type),
                "description": .string(property.description)
            ]
            if let cases = property.enum {
                schema["enum"] = .array(cases.map { .string($0) })
            }
            properties[name] = .object(schema)
        }
        return .object([
            "type": .string(parameters.type),
            "properties": .object(properties),
            "required": .array(parameters.required.map { .string($0) })
        ])
    }

    private static var controlTools: [HypeMCPTool] {
        [
            tool(
                "hype_get_app_state",
                "Return the active Hype app state, open stacks, current card, selection, and MCP policy.",
                [:]
            ),
            tool(
                "hype_list_open_stacks",
                "List open stacks visible to the live Hype automation registry.",
                [:]
            ),
            tool(
                "hype_get_stack_document",
                "Return the full active HypeDocument as JSON, including stack/card/background/part scripts and attributes. Local privileged MCP/debug boundary only.",
                [:]
            ),
            tool(
                "hype_get_object",
                "Return a full stack, card, background, or part object by UUID or case-insensitive name.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false)
                ]
            ),
            tool(
                "hype_canvas_hit_test",
                "Diagnose logical canvas hit testing at a card coordinate. Live Hype adds AppKit routed-view diagnostics.",
                [
                    "x": ("number", "Canvas X coordinate in points.", true),
                    "y": ("number", "Canvas Y coordinate in points.", true),
                    "card_id": ("string", "Optional card UUID. Defaults to current card.", false)
                ]
            ),
            tool(
                "hype_open_script_editor",
                "Open Hype's single script editor window for a stack, card, background, or part. The live app enforces stack userLevel.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false)
                ]
            ),
            tool(
                "hype_dispatch_message",
                "Dispatch a HypeTalk message such as mouseUp to an existing object through the normal runtime MessageDispatcher path.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false),
                    "message": ("string", "Message name, e.g. mouseUp.", true)
                ]
            ),
            tool(
                "hype_get_preferences",
                "Read all MCP-exposed Hype preferences. Secret values are redacted to boolean status.",
                [:]
            ),
            tool(
                "hype_set_preference",
                "Set a non-secret Hype preference by descriptor name.",
                [
                    "name": ("string", "Preference descriptor name, e.g. ai.provider or openai.model", true),
                    "value": ("string", "New scalar preference value", true)
                ]
            ),
            tool(
                "hype_set_secret",
                "Store an MCP-exposed provider secret in Keychain. Values are never returned by any MCP resource or tool.",
                [
                    "name": ("string", "Secret name: openai, llama-swap, z.ai, minimax, meshy, or pexels.", true),
                    "value": ("string", "Secret value to store", true)
                ]
            ),
            tool(
                "hype_delete_secret",
                "Delete an MCP-exposed provider secret from Keychain.",
                [
                    "name": ("string", "Secret name: openai, llama-swap, z.ai, minimax, meshy, or pexels.", true)
                ]
            ),
            tool(
                "hype_set_script",
                "Set a stack, card, background, or part script after parser validation. Empty scripts are allowed.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false),
                    "script": ("string", "HypeTalk script to store.", true),
                    "validate": ("string", "Optional true/false. Defaults to true.", false)
                ]
            ),
            tool(
                "hype_replace_part",
                "Replace one existing Part from full JSON previously read from hype_get_object or hype://stack/{id}/part/{partId}/full. Useful for complete attribute mutation.",
                [
                    "part_json": ("string", "Full JSON object for the replacement Part. The id must already exist.", true),
                    "validate_script": ("string", "Optional true/false. Defaults to true.", false)
                ]
            ),
            tool(
                "hype_run_existing_tool",
                "Run one existing Hype authoring tool against the active stack. Prefer preview/apply for multi-tool edits.",
                [
                    "tool_name": ("string", "Existing Hype tool name, e.g. create_button or set_part_property", true),
                    "arguments_json": ("string", "JSON object of tool arguments", false)
                ]
            ),
            tool(
                "hype_preview_transaction",
                "Preview one or more existing Hype tool calls without applying them to the live stack.",
                [
                    "tool_calls_json": ("string", "JSON array: [{\"tool_name\":\"create_button\",\"arguments\":{...}}]", false),
                    "tool_name": ("string", "Single existing Hype tool name when tool_calls_json is omitted", false),
                    "arguments_json": ("string", "JSON object for the single tool call", false),
                    "prompt": ("string", "Human-readable reason for the transaction", false)
                ]
            ),
            tool(
                "hype_apply_transaction",
                "Apply a previously previewed MCP transaction to the active stack.",
                [
                    "transaction_id": ("string", "Transaction UUID returned by hype_preview_transaction", true)
                ]
            ),
            tool(
                "hype_rollback_transaction",
                "Discard a previously previewed MCP transaction without applying it.",
                [
                    "transaction_id": ("string", "Transaction UUID returned by hype_preview_transaction", true)
                ]
            ),
            tool(
                "hype_create_test_stack",
                "Create or reset the automation backend to a deterministic test stack. Defaults to an acknowledged macOS target unless target_platforms is provided. In the live app this creates a new in-memory stack in the active session.",
                [
                    "name": ("string", "Stack name", false),
                    "target_platforms": ("string", "Optional comma-separated target platforms: macOS, iPhone, iPad, tvOS. Defaults to macOS.", false),
                    "primary_target_platform": ("string", "Optional primary target platform. Defaults to the first selected target.", false)
                ]
            ),
            tool(
                "hype_list_windows",
                "List Hype NSWindow state from inside the live app, without macOS Accessibility permissions.",
                [:]
            ),
            tool(
                "hype_focus_window",
                "Focus a Hype window by window_number, title, or kind. Kinds include script_debugger, script_editor, document, and other.",
                [
                    "window_number": ("number", "NSWindow windowNumber from hype_list_windows.", false),
                    "title": ("string", "Exact or case-insensitive substring title match.", false),
                    "kind": ("string", "Window kind: script_debugger, script_editor, document, or other.", false)
                ]
            ),
            tool(
                "hype_wait_for_window",
                "Poll live Hype NSWindow state until a matching window exists, and optionally until it is key.",
                [
                    "window_number": ("number", "Optional NSWindow windowNumber from hype_list_windows.", false),
                    "title": ("string", "Optional exact or case-insensitive substring title match.", false),
                    "kind": ("string", "Optional window kind: script_debugger, script_editor, document, or other.", false),
                    "key": ("boolean", "Optional true to wait until the window is key.", false),
                    "timeout_ms": ("number", "Timeout in milliseconds. Defaults to 5000.", false)
                ]
            ),
            tool(
                "hype_list_menu_commands",
                "List debug-server menu automation commands that can be triggered without macOS Accessibility permissions.",
                [:]
            ),
            tool(
                "hype_trigger_menu_command",
                "Trigger one Hype menu command through the same app notification path used by the menu item. Use hype_list_menu_commands for stable command ids.",
                [
                    "command": ("string", "Stable command id or visible label, e.g. script_debugger, show_console, next_card, select_tool:button.", true),
                    "argument": ("string", "Optional command argument. Used by select_tool and set_target_emulation.", false),
                    "scope": ("string", "Optional true/false. Defaults to true for document-scoped commands.", false)
                ]
            ),
            tool(
                "hype_get_script_debugger_state",
                "Return script debugger trace entries, breakpoints, watchpoints, scoped variables, globals, and runtime budget pressure.",
                [
                    "max_entries": ("number", "Maximum newest trace entries to return. Defaults to 200.", false),
                    "frame_budget_ms": ("number", "Frame budget in milliseconds for pressure summaries. Defaults to 16.67.", false),
                    "include_diagnostics": ("boolean", "Include detailed statement/expression/property counters. Defaults to true.", false)
                ]
            ),
            tool(
                "hype_set_script_tracing",
                "Enable or pause live HypeTalk script tracing.",
                [
                    "enabled": ("boolean", "Whether tracing should be enabled.", true)
                ]
            ),
            tool(
                "hype_clear_script_trace",
                "Clear recorded script trace entries and reset watchpoint baselines.",
                [:]
            ),
            tool(
                "hype_open_script_trace_source",
                "Open the script editor for a trace source.",
                [
                    "source_kind": ("string", "Trace source kind: part, card, background, stack, or hype.", true),
                    "object_id": ("string", "Source object UUID. Required for part/card/background.", false)
                ]
            ),
            tool(
                "hype_add_script_breakpoint",
                "Add a debugger-session breakpoint matched against source kind, object id, handler, and optional line.",
                [
                    "source_kind": ("string", "Trace source kind: part, card, background, stack, or hype.", false),
                    "object_id": ("string", "Optional source object UUID.", false),
                    "handler": ("string", "Optional handler name.", false),
                    "line": ("number", "Optional handler line number.", false)
                ]
            ),
            tool(
                "hype_remove_script_breakpoint",
                "Remove a script debugger breakpoint by UUID.",
                [
                    "id": ("string", "Breakpoint UUID.", true)
                ]
            ),
            tool(
                "hype_add_script_watchpoint",
                "Add a debugger-session watchpoint for a local, global, special, or auto-scoped variable name.",
                [
                    "scope": ("string", "auto, local, global, or special. Defaults to auto.", false),
                    "name": ("string", "Variable name to watch.", true)
                ]
            ),
            tool(
                "hype_remove_script_watchpoint",
                "Remove a script debugger watchpoint by UUID.",
                [
                    "id": ("string", "Watchpoint UUID.", true)
                ]
            ),
            tool(
                "hype_resume_script_execution",
                "Resume the currently halted HypeTalk handler, if a breakpoint has paused execution.",
                [:]
            ),
            tool(
                "hype_step_into_script_execution",
                "Resume the currently halted HypeTalk handler and halt again at the next handler entry.",
                [:]
            ),
            tool(
                "hype_step_over_script_execution",
                "Resume the currently halted HypeTalk handler and halt again at the next handler entry. Statement-level stepping is not yet available.",
                [:]
            ),
            tool(
                "hype_wait_for_debugger_pause",
                "Poll until script execution is halted in the debugger, optionally matching reason, handler, source kind, or line.",
                [
                    "reason": ("string", "Optional pause reason to match, e.g. breakpoint, stepInto, or stepOver.", false),
                    "handler": ("string", "Optional handler name to match.", false),
                    "source_kind": ("string", "Optional source kind to match.", false),
                    "line": ("number", "Optional source line to match.", false),
                    "timeout_ms": ("number", "Timeout in milliseconds. Defaults to 5000.", false)
                ]
            ),
            tool(
                "hype_step_script_execution_and_wait",
                "Step into or over from a halted script and wait for the next debugger pause.",
                [
                    "step": ("string", "Step mode: into or over.", false),
                    "timeout_ms": ("number", "Timeout in milliseconds. Defaults to 5000.", false)
                ]
            ),
            tool(
                "hype_get_script_editor_state",
                "Return resolved script-editor target metadata and debugger breakpoints for a stack, card, background, or part.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false)
                ]
            ),
            tool(
                "hype_toggle_script_editor_breakpoint",
                "Set, clear, or toggle a debugger breakpoint for the script-editor target line.",
                [
                    "object_type": ("string", "Object type: stack, card, background, or part.", true),
                    "id_or_name": ("string", "UUID or case-insensitive name. Omit only for stack.", false),
                    "line": ("number", "One-based script line number.", true),
                    "action": ("string", "toggle, add, or remove. Defaults to toggle.", false)
                ]
            )
        ]
    }

    private static func tool(
        _ name: String,
        _ description: String,
        _ params: [String: (String, String, Bool)]
    ) -> HypeMCPTool {
        var properties: [String: HypeMCPJSONValue] = [:]
        var required: [HypeMCPJSONValue] = []
        for (key, value) in params {
            properties[key] = .object([
                "type": .string(value.0),
                "description": .string(value.1)
            ])
            if value.2 {
                required.append(.string(key))
            }
        }
        return HypeMCPTool(
            name: name,
            description: description,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(properties),
                "required": .array(required)
            ])
        )
    }
}

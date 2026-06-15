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
        "hype_get_script_debugger_state",
        "hype_set_script_tracing",
        "hype_clear_script_trace",
        "hype_open_script_trace_source"
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
                "hype_get_script_debugger_state",
                "Return script debugger globals, trace entries, profiling counters, and script-runtime budget pressure for the live Hype session.",
                [
                    "max_entries": ("number", "Maximum newest trace entries to return. Defaults to 200.", false),
                    "frame_budget_ms": ("number", "Runtime budget in milliseconds used for budget pressure calculations. Defaults to 16.67 ms.", false),
                    "include_diagnostics": ("boolean", "Include detailed profiler counters on each trace entry. Defaults to true.", false)
                ]
            ),
            tool(
                "hype_set_script_tracing",
                "Enable or pause live HypeTalk tracing in the Script Debugger recorder.",
                [
                    "enabled": ("boolean", "true to trace script handlers, false to pause tracing.", true)
                ]
            ),
            tool(
                "hype_clear_script_trace",
                "Clear recorded HypeTalk script trace entries without changing globals.",
                [:]
            ),
            tool(
                "hype_open_script_trace_source",
                "Open the source script referenced by a trace entry source object.",
                [
                    "source_kind": ("string", "Trace source kind: part, card, background, stack, or hype.", true),
                    "object_id": ("string", "UUID for part/card/background sources. Omit for stack or hype.", false)
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

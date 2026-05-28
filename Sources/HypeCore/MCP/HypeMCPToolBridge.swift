import Foundation

public enum HypeMCPToolBridge {
    public static let mcpControlToolNames: Set<String> = [
        "hype_get_app_state",
        "hype_list_open_stacks",
        "hype_get_preferences",
        "hype_set_preference",
        "hype_set_secret",
        "hype_delete_secret",
        "hype_run_existing_tool",
        "hype_preview_transaction",
        "hype_apply_transaction",
        "hype_rollback_transaction",
        "hype_create_test_stack"
    ]

    public static var allTools: [HypeMCPTool] {
        HypeToolDefinitions.allTools.map(mcpTool(from:)) + controlTools
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
                "Create or reset the automation backend to a deterministic test stack. In the live app this creates a new in-memory stack in the active session.",
                [
                    "name": ("string", "Stack name", false)
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

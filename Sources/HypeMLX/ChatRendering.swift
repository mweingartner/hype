#if canImport(MLXLMCommon)
import Foundation
import HypeCore
import MLXLMCommon

/// Translates Hype's chat vocabulary into the dictionaries a model's own chat
/// template consumes, and MLX's parsed tool calls back into Hype's.
enum ChatRendering {
    static let imageOmittedNote = "[An image was attached, but this Built-in model build reads text only.]"

    static func templateMessages(from messages: [OllamaMessage]) -> [[String: any Sendable]] {
        messages.map { message in
            var rendered: [String: any Sendable] = ["role": message.role]
            var content = message.content ?? ""
            if let images = message.images, !images.isEmpty {
                content = content.isEmpty ? imageOmittedNote : content + "\n\n" + imageOmittedNote
            }
            rendered["content"] = content
            if let calls = message.tool_calls, !calls.isEmpty {
                rendered["tool_calls"] = calls.map { call -> [String: any Sendable] in
                    let arguments: [String: any Sendable] = call.function.arguments.mapValues { $0 as any Sendable }
                    return [
                        "type": "function",
                        "function": ["name": call.function.name, "arguments": arguments] as [String: any Sendable],
                    ]
                }
            }
            return rendered
        }
    }

    static func templateTools(from tools: [OllamaTool]) -> [[String: any Sendable]] {
        tools.map { tool in
            var properties: [String: any Sendable] = [:]
            for (name, property) in tool.function.parameters.properties {
                var schema: [String: any Sendable] = [
                    "type": property.type,
                    "description": property.description,
                ]
                if let values = property.enum, !values.isEmpty {
                    schema["enum"] = values
                }
                properties[name] = schema
            }
            let parameters: [String: any Sendable] = [
                "type": tool.function.parameters.type,
                "properties": properties,
                // Sorted so the rendered prompt — and its cached prefix — is stable.
                "required": tool.function.parameters.required.sorted(),
            ]
            return [
                "type": tool.type,
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "parameters": parameters,
                ] as [String: any Sendable],
            ]
        }
    }

    /// Every Hype authoring tool takes string arguments; models sometimes emit
    /// numbers, booleans or nested JSON. Flatten them the way the HTTP clients do.
    static func toolCall(from call: ToolCall) -> BuiltInToolCall {
        BuiltInToolCall(
            name: call.function.name,
            arguments: call.function.arguments.mapValues(string(from:))
        )
    }

    static func string(from value: JSONValue) -> String {
        switch value {
        case .null: return ""
        case .bool(let flag): return flag ? "true" : "false"
        case .int(let number): return String(number)
        case .double(let number):
            return number == number.rounded() && abs(number) < 1e15 ? String(Int(number)) : String(number)
        case .string(let text): return text
        case .array, .object:
            guard let data = try? JSONEncoder().encode(value),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }
}
#endif

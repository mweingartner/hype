import Foundation

public enum BraveSearchError: Error, LocalizedError, Sendable {
    case invalidEndpoint
    case unavailable
    case timedOut
    case http(Int)
    case protocolError(String)
    case responseTooLarge
    case invalidArguments
    case unknownTool(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Enter an HTTP or HTTPS MCP URL in Settings → Services → Brave Search, without credentials, a query, or a fragment."
        case .unavailable:
            return "Brave Search Bridge is unavailable. Open Brave Search Bridge on the bridge Mac, keep that Mac awake and logged in, and check the MCP URL in Settings → Services. Localhost refers to the Mac running Hype."
        case .timedOut:
            return "Brave Search Bridge timed out. Check that the bridge is running and reachable, then retry."
        case .http(let status):
            return "Brave Search Bridge returned HTTP \(status). Check the bridge and MCP URL; Brave feature access and quota depend on your subscription."
        case .protocolError(let message):
            return "Brave Search MCP error: \(message)"
        case .responseTooLarge:
            return "Brave Search returned too much data. Request fewer results or a smaller LLM context."
        case .invalidArguments:
            return "Brave arguments_json must be a JSON object with types matching the discovered inputSchema."
        case .unknownTool(let name):
            return "Brave tool '\(name)' was not discovered on this bridge. Call list_brave_tools to check its available tools."
        }
    }
}

import Foundation

public enum ChatterSpeechConfiguration {
    public static let enabledKey = "hype.speech.chatter.enabled"
    public static let bridgeURL = URL(fileURLWithPath: "/Applications/Chatter.app/Contents/MacOS/chatter-mcp")
    public static func makeClient() -> ChatterSpeechClient {
        let bridge = MCPStdioBridgeClient(executableURL: bridgeURL)
        return ChatterSpeechClient(toolCall: { try await bridge.callTool($0, arguments: $1) })
    }
}

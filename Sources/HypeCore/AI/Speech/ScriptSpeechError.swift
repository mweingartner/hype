import Foundation

public enum ScriptSpeechError: Error, LocalizedError, Sendable {
    case invalid(String), unavailable(String), failed(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message), .failed(let message): return message
        }
    }
}

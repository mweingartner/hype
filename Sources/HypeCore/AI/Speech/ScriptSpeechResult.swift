import Foundation

public struct ScriptSpeechResult: Sendable, Equatable {
    public var value: String
    public var warnings: [String]
    public init(value: String = "", warnings: [String] = []) { self.value = value; self.warnings = warnings }
}

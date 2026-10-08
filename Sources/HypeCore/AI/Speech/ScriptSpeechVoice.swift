import Foundation

public struct ScriptSpeechVoice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDefault: Bool
    public let ready: Bool
    public let supportsTone: Bool
    public init(id: String, name: String, isDefault: Bool = false, ready: Bool = true, supportsTone: Bool = false) {
        self.id = id; self.name = name; self.isDefault = isDefault
        self.ready = ready; self.supportsTone = supportsTone
    }
}

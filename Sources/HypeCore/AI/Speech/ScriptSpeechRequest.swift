import Foundation

/// Nil options are resolved by the selected service, not persisted in Hype.
public struct ScriptSpeechRequest: Sendable, Equatable {
    public var text: String
    public var voice: String?
    public var tone: String?
    public var pace: Double?
    public var quality: String?
    public var output: String?
    public init(text: String, voice: String? = nil, tone: String? = nil, pace: Double? = nil, quality: String? = nil, output: String? = nil) {
        self.text = text; self.voice = voice; self.tone = tone
        self.pace = pace; self.quality = quality; self.output = output
    }
    public var hasOptions: Bool { voice != nil || tone != nil || pace != nil || quality != nil || output != nil }
    public func validate() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 100_000 else {
            throw ScriptSpeechError.invalid("Speech needs non-empty text of at most 100,000 UTF-8 bytes.")
        }
        if let pace, !pace.isFinite || !(0.5...2).contains(pace) {
            throw ScriptSpeechError.invalid("Speech pace must be between 0.5 and 2.0.")
        }
        if let quality, !["responsive", "balanced", "studio"].contains(quality.lowercased()) {
            throw ScriptSpeechError.invalid("Speech quality must be responsive, balanced, or studio.")
        }
        if let output, !["direct", "wav"].contains(output.lowercased()) {
            throw ScriptSpeechError.invalid("Speech output must be direct or wav.")
        }
    }
}

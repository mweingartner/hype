import Foundation

/// Optional spoken-output surface for AI-generated text.
///
/// HypeCore does not play audio directly; the app target injects an
/// implementation that can use OpenAI speech and AVFoundation. Tests
/// and non-UI contexts use the no-op provider.
public protocol SpeechOutputProvider: Sendable {
    func speakAIResponse(_ text: String, source: String) async
}

public struct StubSpeechOutputProvider: SpeechOutputProvider, Sendable {
    public init() {}
    public func speakAIResponse(_ text: String, source: String) async {}
}

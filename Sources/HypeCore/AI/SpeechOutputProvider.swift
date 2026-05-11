import Foundation

/// Optional spoken-output surface for AI-generated text.
///
/// HypeCore does not play audio directly; the app target injects an
/// implementation that can use OpenAI speech and AVFoundation. Tests
/// and non-UI contexts use the no-op provider.
public protocol SpeechOutputProvider: Sendable {
    func speakAIResponse(_ text: String, source: String) async
    func speakScriptText(_ text: String, source: String) async
}

public extension SpeechOutputProvider {
    func speakScriptText(_ text: String, source: String) async {
        await speakAIResponse(text, source: source)
    }
}

public struct StubSpeechOutputProvider: SpeechOutputProvider, Sendable {
    public init() {}
    public func speakAIResponse(_ text: String, source: String) async {}
    public func speakScriptText(_ text: String, source: String) async {}
}

/// Optional speech-input surface used by HypeTalk's `activateListener` runtime.
///
/// HypeCore owns the command semantics and message dispatch, while the app target
/// injects a provider backed by the configured speech-recognition engine.
public protocol SpeechListenerProvider: Sendable {
    func startSpeechListener(onTranscript: @escaping @Sendable (String) async -> Void) async throws
    func stopSpeechListener() async
}

public struct StubSpeechListenerProvider: SpeechListenerProvider, Sendable {
    public init() {}
    public func startSpeechListener(onTranscript: @escaping @Sendable (String) async -> Void) async throws {}
    public func stopSpeechListener() async {}
}

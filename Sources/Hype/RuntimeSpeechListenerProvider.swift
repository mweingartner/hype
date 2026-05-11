import Combine
import Foundation
import HypeCore

actor RuntimeSpeechListenerProvider: SpeechListenerProvider {
    static let shared = RuntimeSpeechListenerProvider()

    private var bridge: RuntimeSpeechListenerBridge?

    func startSpeechListener(onTranscript: @escaping @Sendable (String) async -> Void) async throws {
        let bridge = await bridgeOnMain()
        await bridge.start(onTranscript: onTranscript)
    }

    func stopSpeechListener() async {
        guard let bridge else { return }
        await bridge.stop()
    }

    private func bridgeOnMain() async -> RuntimeSpeechListenerBridge {
        if let bridge {
            return bridge
        }
        let bridge = await MainActor.run { RuntimeSpeechListenerBridge() }
        self.bridge = bridge
        return bridge
    }
}

@MainActor
private final class RuntimeSpeechListenerBridge: @unchecked Sendable {
    private let capture = AISpeechCapture()
    private var transcriptCancellable: AnyCancellable?
    private var onTranscript: (@Sendable (String) async -> Void)?
    private var active = false

    func start(onTranscript: @escaping @Sendable (String) async -> Void) {
        self.onTranscript = onTranscript
        active = true
        if transcriptCancellable == nil {
            transcriptCancellable = capture.transcriptDidFinalize.sink { [weak self] text in
                Task { @MainActor in
                    await self?.handleFinalTranscript(text)
                }
            }
        }
        Task { await capture.start() }
    }

    func stop() {
        active = false
        onTranscript = nil
        transcriptCancellable?.cancel()
        transcriptCancellable = nil
        capture.stop()
    }

    private func handleFinalTranscript(_ text: String) async {
        let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard active, !transcript.isEmpty else { return }
        let callback = onTranscript
        Task {
            await callback?(transcript)
        }
        Task { @MainActor in
            if self.active {
                await self.capture.start()
            }
        }
    }
}

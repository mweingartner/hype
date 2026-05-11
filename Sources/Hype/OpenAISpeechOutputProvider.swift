import AVFoundation
import Foundation
import HypeCore

actor OpenAISpeechOutputProvider: SpeechOutputProvider {
    static let shared = OpenAISpeechOutputProvider()

    private var speechPlayer: AVAudioPlayer?

    func speakAIResponse(_ text: String, source: String) async {
        guard UserDefaults.standard.bool(forKey: HypeAIConfiguration.speakAssistantResponsesKey) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Keep speech responsive and avoid accidentally voicing large tool/debug payloads.
        let spokenText = String(trimmed.prefix(1200))
        Task {
            await self.generateAndPlay(text: spokenText, source: source)
        }
    }

    private func generateAndPlay(text: String, source: String) async {
        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
            let client = OpenAISpeechClient(apiKey: apiKey)
            let data = try await client.speech(
                text: text,
                model: HypeAIConfiguration.openAITTSModel(),
                voice: HypeAIConfiguration.openAIVoice()
            )
            let player = try AVAudioPlayer(data: data)
            speechPlayer = player
            player.prepareToPlay()
            player.play()
        } catch {
            HypeLogger.shared.warn("OpenAI speech output failed: \(error.localizedDescription)", source: source)
        }
    }
}

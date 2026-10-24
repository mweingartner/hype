import AVFoundation
import Foundation
import HypeCore

@MainActor
private final class SystemSpeechOutput {
    static let shared = SystemSpeechOutput()

    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        synthesizer.speak(utterance)
    }
}

actor OpenAISpeechOutputProvider: SpeechOutputProvider {
    static let shared = OpenAISpeechOutputProvider()

    private var speechPlayer: AVAudioPlayer?
    private var responseSpeech = AIResponseSpeechPlanner()

    func speak(_ request: ScriptSpeechRequest, source: String) async throws -> ScriptSpeechResult {
        if UserDefaults.standard.bool(forKey: ChatterSpeechConfiguration.enabledKey) {
            return try await ChatterSpeechConfiguration.makeClient().speak(request)
        }
        try request.validate()
        guard !request.hasOptions else {
            throw ScriptSpeechError.unavailable("Enable Chatter in Settings → Speech to use speech options or WAV output.")
        }
        await speakScriptText(request.text, source: source)
        return ScriptSpeechResult()
    }

    func speechVoices() async throws -> [ScriptSpeechVoice] {
        guard UserDefaults.standard.bool(forKey: ChatterSpeechConfiguration.enabledKey) else {
            throw ScriptSpeechError.unavailable("Enable Chatter in Settings → Speech to list its voices.")
        }
        return try await ChatterSpeechConfiguration.makeClient().voices()
    }

    func speakAIResponse(_ text: String, source: String) async {
        await speakAIResponse(text, source: source, responseID: UUID())
    }

    func speakAIResponse(_ text: String, source: String, responseID: UUID) async {
        guard UserDefaults.standard.bool(forKey: HypeAIConfiguration.speakAssistantResponsesKey) else { return }
        guard let spokenText = responseSpeech.prepare(text, responseID: responseID) else { return }
        Task {
            if UserDefaults.standard.bool(forKey: ChatterSpeechConfiguration.enabledKey) {
                do { _ = try await ChatterSpeechConfiguration.makeClient().speak(ScriptSpeechRequest(text: spokenText)) }
                catch { HypeLogger.shared.warn(error.localizedDescription, source: source) }
                return
            }
            _ = await self.generateAndPlay(text: spokenText, source: source)
        }
    }

    func speakScriptText(_ text: String, source: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if UserDefaults.standard.bool(forKey: ChatterSpeechConfiguration.enabledKey) {
            do { _ = try await ChatterSpeechConfiguration.makeClient().speak(ScriptSpeechRequest(text: text)) }
            catch { HypeLogger.shared.warn(error.localizedDescription, source: source) }
            return
        }
        let spokenText = String(trimmed.prefix(1200))
        if UserDefaults.standard.bool(forKey: HypeAIConfiguration.speakAssistantResponsesKey),
           await generateAndPlay(text: spokenText, source: source) {
            return
        }
        await MainActor.run {
            SystemSpeechOutput.shared.speak(spokenText)
        }
    }

    private func generateAndPlay(text: String, source: String) async -> Bool {
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
            return true
        } catch {
            HypeLogger.shared.warn("OpenAI speech output failed: \(error.localizedDescription)", source: source)
            return false
        }
    }
}

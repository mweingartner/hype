import Foundation
import AVFoundation
import Speech
import Combine
import HypeCore

/// Voice capture pipeline for the AI Chat panel.
///
/// Wraps `SFSpeechRecognizer` + `AVAudioEngine` so the chat panel
/// only deals with three things:
/// - `transcript`: currently-recognized text. Updates incrementally
///    while listening, finalizes when the user stops.
/// - `state`: idle / listening / unavailable / error.
/// - `start()` / `stop()`: explicit control.
///
/// The controller emits `transcriptDidFinalize` when the recognizer
/// returns `isFinal == true` — that's the signal the chat panel uses
/// to auto-submit the message (per the spec: "executes the command
/// when the speaker is complete as if enter was hit").
///
/// Permissions are requested lazily on first `start()`. `unavailable`
/// covers both denied permissions and missing on-device recognition
/// support — both should produce a graceful UI state, not a crash.
@MainActor
final class AISpeechCapture: ObservableObject {

    enum State: Equatable {
        case idle
        case listening
        case transcribing
        case unavailable(reason: String)
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript: String = ""

    /// Fires every time the recognizer reports `isFinal == true` —
    /// i.e. the user has paused for long enough that the system
    /// considers the utterance complete. The chat panel observes
    /// this to auto-submit, mirroring the "press enter" behavior.
    let transcriptDidFinalize = PassthroughSubject<String, Never>()

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var openAIRecorder: AVAudioRecorder?
    private var openAIRecordingURL: URL?
    private var captureProvider: HypeSpeechInputProvider?
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init() {
        // SFSpeechRecognizer.isAvailable is observable, but we only
        // need it lazily on start().
    }

    var isListening: Bool { state == .listening }
    var isTranscribing: Bool { state == .transcribing }

    func toggle() {
        if isListening {
            Task { await stopAndFinalizeIfNeeded() }
        } else {
            Task { await start() }
        }
    }

    func start() async {
        let provider = HypeAIConfiguration.selectedSpeechInputProvider()
        captureProvider = provider
        transcript = ""

        if provider == .openAI {
            await startOpenAIRecording()
            return
        }

        guard recognizer?.isAvailable == true else {
            state = .unavailable(reason: "Speech recognition isn't available on this device")
            return
        }

        let speechAuth = await requestSpeechAuthorization()
        guard speechAuth == .authorized else {
            state = .unavailable(reason: speechAuthorizationMessage(speechAuth))
            return
        }

        let micAuth = await requestMicrophoneAuthorization()
        guard micAuth else {
            state = .unavailable(reason: "Microphone access denied — enable in System Settings → Privacy & Security → Microphone.")
            return
        }

        do {
            try beginCapture()
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        openAIRecorder?.stop()
        openAIRecorder = nil
        if let url = openAIRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        openAIRecordingURL = nil
        captureProvider = nil
        state = .idle
    }

    func stopAndFinalizeIfNeeded() async {
        guard captureProvider == .openAI else {
            stop()
            return
        }

        openAIRecorder?.stop()
        openAIRecorder = nil
        guard let url = openAIRecordingURL else {
            state = .idle
            return
        }

        state = .transcribing
        defer {
            try? FileManager.default.removeItem(at: url)
            openAIRecordingURL = nil
            captureProvider = nil
        }

        do {
            let apiKey = try KeychainStore.getSecret(account: KeychainStore.openAIAPIKeyAccount)
            let text = try await OpenAISpeechClient(apiKey: apiKey).transcribe(
                audioFileURL: url,
                model: HypeAIConfiguration.openAITranscriptionModel()
            )
            transcript = text
            state = .idle
            transcriptDidFinalize.send(text)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Permissions

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        if #available(macOS 14, *) {
            return await AVCaptureDevice.requestAccess(for: .audio)
        } else {
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func speechAuthorizationMessage(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: return ""
        case .denied: return "Speech recognition denied — enable in System Settings → Privacy & Security → Speech Recognition."
        case .restricted: return "Speech recognition is restricted on this device."
        case .notDetermined: return "Speech recognition permission not yet determined."
        @unknown default: return "Speech recognition unavailable."
        }
    }

    // MARK: - Audio engine

    private func startOpenAIRecording() async {
        let micAuth = await requestMicrophoneAuthorization()
        guard micAuth else {
            state = .unavailable(reason: "Microphone access denied — enable in System Settings → Privacy & Security → Microphone.")
            return
        }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("hype-openai-speech-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            recorder.record()
            openAIRecorder = recorder
            openAIRecordingURL = url
            state = .listening
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func beginCapture() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "AISpeechCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"])
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when available — avoids round-tripping audio
        // off the machine and respects the user's privacy choice.
        if #available(macOS 13, *), recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Empty format check — happens when Hype is run inside
        // certain sandboxed environments without an active mic.
        guard format.sampleRate > 0 else {
            throw NSError(domain: "AISpeechCapture", code: -2, userInfo: [NSLocalizedDescriptionKey: "No audio input device available"])
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.transcriptDidFinalize.send(self.transcript)
                        self.stop()
                    }
                }
                if error != nil {
                    self.stop()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }
}

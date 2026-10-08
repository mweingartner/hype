import SwiftUI
import HypeCore

struct ChatterSpeechSettingsSection: View {
    @AppStorage(ChatterSpeechConfiguration.enabledKey) private var enabled = false
    @State private var voices: [ScriptSpeechVoice] = []
    @State private var status = ""
    @State private var isLoading = false
    @State private var requestID = UUID()
    @State private var requestTask: Task<Void, Never>?

    var body: some View {
        Section("Local Chatter Speech") {
            Toggle("Use Chatter for speech output", isOn: $enabled)
                .help("Use the local Chatter service for speak, say, and enabled AI spoken replies.")
            HStack {
                Button("Refresh Voices", action: refreshVoices)
                    .disabled(isLoading)
                if isLoading {
                    ProgressView().controlSize(.small).accessibilityLabel("Loading Chatter voices")
                    Button("Cancel", action: cancelRefresh)
                }
            }
            if !status.isEmpty {
                Text(status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(voices) { voice in
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name + (voice.isDefault ? " · Chatter default" : ""))
                    Text((voice.ready ? "Ready" : "Needs setup") + " · " + (voice.supportsTone ? "Supports tone" : "Delivery follows recordings"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Keep Chatter running on this Mac. Missing options use Chatter's current default voice, pace, tone, and quality. Direct output plays through Chatter; WAV output uses its configured folder and Studio quality. Recorded voices do not support tone control. Connection credentials stay with Chatter's local bridge.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("speak \"Hello\" with voice \"Ryan\", tone \"warm\", pace 0.9, quality \"studio\", output \"wav\"")
                .font(.caption.monospaced()).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear(perform: cancelRefresh)
    }

    private func refreshVoices() {
        cancelRefresh()
        let id = UUID()
        requestID = id
        isLoading = true
        status = "Loading voices…"
        requestTask = Task { @MainActor in
            do {
                let discovered = try await ChatterSpeechConfiguration.makeClient().voices()
                guard requestID == id, !Task.isCancelled else { return }
                voices = discovered
                status = "Connected · \(discovered.count) saved voices."
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                voices = []
                status = error.localizedDescription
            }
            isLoading = false
            requestTask = nil
        }
    }

    private func cancelRefresh() {
        requestID = UUID()
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        if status == "Loading voices…" { status = "Voice discovery cancelled." }
    }
}

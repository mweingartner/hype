import AppKit
import AVFoundation
import HypeCore

/// AppKit-hosted audio recorder for `audioRecorder` parts.
///
/// The view mirrors `AudioRecorderRenderer` visually — mic icon +
/// duration label + recording dot — but driven by the actual
/// `AVAudioRecorder` engine. The host owns:
/// - mic permission (lazy, on first start)
/// - the recorder's AVAudioRecorder instance
/// - a Timer that ticks ~10x/sec while recording so the part's
///   `audioDuration` stays in sync with engine time
/// - a closure (`onStateChange`) the chat panel uses to write the
///   live recording flag + duration back into the document
///
/// The "ask me to start recording" surface is the part's
/// `audioRecording` boolean — flipping it true via HypeTalk or AI
/// triggers `start()`; flipping back to false stops. This keeps the
/// HypeTalk model simple — no new verbs.
final class AudioRecorderHostNSView: NSView {

    /// Closure that fires every time recording state changes
    /// (started / stopped / duration tick). The chat panel /
    /// `CardCanvasView` coordinator writes the values back into
    /// the document so HypeTalk reads stay in sync.
    var onStateChange: ((_ recording: Bool, _ duration: Double, _ outputPath: String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var tickTimer: Timer?
    private(set) var lastOutputPath: String = ""
    private(set) var isRecording = false

    private let micLabel = NSTextField(labelWithString: "🎤")
    private let durationLabel = NSTextField(labelWithString: "00:00")
    private let dotView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        micLabel.translatesAutoresizingMaskIntoConstraints = false
        micLabel.font = .systemFont(ofSize: 18)
        addSubview(micLabel)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        durationLabel.alignment = .left
        addSubview(durationLabel)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.isHidden = true
        addSubview(dotView)

        NSLayoutConstraint.activate([
            micLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            micLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            durationLabel.leadingAnchor.constraint(equalTo: micLabel.trailingAnchor, constant: 12),
            durationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            dotView.centerYAnchor.constraint(equalTo: topAnchor, constant: 12),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // No explicit deinit teardown — Timer + AVAudioRecorder are
    // nonisolated and Swift 6's strict concurrency rejects access
    // from deinit. CardCanvasView calls `.stop()` before removing
    // the host (see `updateAudioRecorderViews` cleanup branch),
    // which is the path that runs in normal use.

    /// Apply the latest part config. If the part flipped from
    /// not-recording to recording, kick off the engine. If from
    /// recording to not, stop it.
    func apply(_ part: Part) {
        durationLabel.stringValue = Self.formatDuration(part.audioDuration)
        if part.audioRecording && !isRecording {
            start(part: part)
        } else if !part.audioRecording && isRecording {
            stop()
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        tickTimer?.invalidate()
        tickTimer = nil
        isRecording = false
        dotView.isHidden = true
        let finalDuration: Double = recorder?.currentTime ?? 0
        onStateChange?(false, finalDuration, lastOutputPath)
    }

    private func start(part: Part) {
        let path: String
        if !part.audioOutputPath.isEmpty {
            path = part.audioOutputPath
        } else {
            let safeName = part.name.replacingOccurrences(of: "/", with: "_")
            let ext = part.audioFormat == "caf" ? "caf" : "m4a"
            path = FileManager.default.temporaryDirectory
                .appendingPathComponent("hype-recorder-\(safeName)-\(UUID().uuidString).\(ext)")
                .path
        }
        lastOutputPath = path
        let url = URL(fileURLWithPath: path)
        // Build settings appropriate for the requested format.
        let settings: [String: Any]
        if part.audioFormat == "caf" {
            settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false
            ]
        } else {
            settings = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        }
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.prepareToRecord()
            rec.record()
            recorder = rec
            isRecording = true
            dotView.isHidden = false
            onStateChange?(true, 0, path)
            // Tick 10x/sec for live duration updates.
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                let dur = rec.currentTime
                self.durationLabel.stringValue = Self.formatDuration(dur)
                self.onStateChange?(true, dur, self.lastOutputPath)
            }
        } catch {
            isRecording = false
            dotView.isHidden = true
            onStateChange?(false, 0, "")
        }
    }

    private nonisolated static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

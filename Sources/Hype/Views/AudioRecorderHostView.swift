import AppKit
import AVFoundation
import HypeCore

/// AppKit-hosted audio recorder + player for `audioRecorder` parts.
///
/// Visually a small panel with a Record button (toggles recording),
/// a Play button (toggles playback of the most recent recording),
/// a duration label, a recording-indicator dot, and a small filename
/// strip. The host owns:
/// - the `AVAudioRecorder` instance + its tick timer
/// - the `AVAudioPlayer` instance + its end-of-play delegate hook
/// - a callback closure (`onStateChange`) the coordinator wires up
///   to write the live recording/playing flags + duration + path
///   back into the document so HypeTalk reads stay in sync.
///
/// Two ways to drive the recorder:
/// 1. **Buttons in the host** (this file). User clicks Record / Play.
/// 2. **Document property flips** via HypeTalk or AI:
///    - `set the recording of recorder "X" to true`  → starts capture
///    - `set the recording of recorder "X" to false` → stops capture
///    - `set the playing of recorder "X" to true`    → plays last file
///    - `set the playing of recorder "X" to false`   → stops playback
///
/// `apply(_:)` reconciles the part's `audioRecording` / `audioPlaying`
/// flags with the host's live state — flipping either flag in the
/// document drives the AppKit engine, and the host's state changes
/// (button presses, end-of-playback) write back via `onStateChange`.
final class AudioRecorderHostNSView: NSView {

    /// Closure that fires every time recorder OR player state
    /// changes (started / stopped / duration tick / playback end).
    /// The coordinator writes the values back into the document so
    /// HypeTalk reads stay in sync.
    var onStateChange: ((_ recording: Bool, _ playing: Bool, _ duration: Double, _ outputPath: String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playerDelegate: PlayerEndDelegate?
    private var tickTimer: Timer?
    private(set) var lastOutputPath: String = ""
    private(set) var isRecording = false
    private(set) var isPlaying = false

    private let recordButton = NSButton()
    private let playButton = NSButton()
    private let durationLabel = NSTextField(labelWithString: "00:00")
    private let dotView = NSView()
    private let fileNameLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 6
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1

        recordButton.translatesAutoresizingMaskIntoConstraints = false
        recordButton.bezelStyle = .rounded
        recordButton.title = "● Record"
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        recordButton.font = .systemFont(ofSize: 11)
        addSubview(recordButton)

        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.bezelStyle = .rounded
        playButton.title = "▶ Play"
        playButton.target = self
        playButton.action = #selector(playButtonClicked)
        playButton.font = .systemFont(ofSize: 11)
        addSubview(playButton)

        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        durationLabel.alignment = .right
        addSubview(durationLabel)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = NSColor.systemRed.cgColor
        dotView.isHidden = true
        addSubview(dotView)

        fileNameLabel.translatesAutoresizingMaskIntoConstraints = false
        fileNameLabel.font = .systemFont(ofSize: 9)
        fileNameLabel.textColor = .secondaryLabelColor
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(fileNameLabel)

        NSLayoutConstraint.activate([
            recordButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            recordButton.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            playButton.leadingAnchor.constraint(equalTo: recordButton.trailingAnchor, constant: 6),
            playButton.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            durationLabel.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            dotView.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -6),
            dotView.centerYAnchor.constraint(equalTo: recordButton.centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            fileNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            fileNameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            fileNameLabel.topAnchor.constraint(equalTo: recordButton.bottomAnchor, constant: 4),
            fileNameLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])

        playButton.isEnabled = false  // No file yet to play.
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Apply (document → live state)

    /// Reconcile the part's `audioRecording` / `audioPlaying` with
    /// the host's engine state. Drives recorder + player from doc
    /// flips so HypeTalk and AI tools can control playback the same
    /// way they control recording.
    func apply(_ part: Part) {
        durationLabel.stringValue = Self.formatDuration(part.audioDuration)
        if !part.audioOutputPath.isEmpty {
            lastOutputPath = part.audioOutputPath
            fileNameLabel.stringValue = (part.audioOutputPath as NSString).lastPathComponent
            playButton.isEnabled = !isRecording && FileManager.default.fileExists(atPath: part.audioOutputPath)
        }
        // Recording reconciliation
        if part.audioRecording && !isRecording {
            start(part: part)
        } else if !part.audioRecording && isRecording {
            stop()
        }
        // Playback reconciliation
        if part.audioPlaying && !isPlaying {
            play()
        } else if !part.audioPlaying && isPlaying {
            stopPlayback()
        }
    }

    // MARK: - Button handlers (live state → document)

    @objc private func recordButtonClicked() {
        if isRecording {
            stop()
        } else {
            // Synthesize a Part-shaped argument for start() — we
            // don't have direct access to the live Part struct here,
            // so we read from the cached lastOutputPath / format
            // hints stored on the host (or fall back to defaults).
            // The full Part is what `apply()` uses; for button-driven
            // start we re-use whatever path/format was last applied.
            startWithCurrentSettings()
        }
    }

    @objc private func playButtonClicked() {
        if isPlaying {
            stopPlayback()
        } else {
            play()
        }
    }

    // MARK: - Recording engine

    func stop() {
        let finalDuration: Double = recorder?.currentTime ?? 0
        recorder?.stop()
        recorder = nil
        tickTimer?.invalidate()
        tickTimer = nil
        isRecording = false
        dotView.isHidden = true
        recordButton.title = "● Record"
        playButton.isEnabled = FileManager.default.fileExists(atPath: lastOutputPath)
        onStateChange?(false, isPlaying, finalDuration, lastOutputPath)
    }

    private var pendingFormat: String = "m4a"
    private var pendingExplicitPath: String = ""

    private func start(part: Part) {
        pendingFormat = part.audioFormat
        pendingExplicitPath = part.audioOutputPath
        startWithCurrentSettings(partName: part.name)
    }

    private func startWithCurrentSettings(partName: String? = nil) {
        // Stop playback if it was running — recording while playing
        // back is meaningless and would feed audio into the mic.
        if isPlaying { stopPlayback() }

        let path: String
        if !pendingExplicitPath.isEmpty {
            path = pendingExplicitPath
        } else {
            let safeName = (partName ?? "recording").replacingOccurrences(of: "/", with: "_")
            let ext = pendingFormat == "caf" ? "caf" : "m4a"
            path = FileManager.default.temporaryDirectory
                .appendingPathComponent("hype-recorder-\(safeName)-\(UUID().uuidString).\(ext)")
                .path
        }
        lastOutputPath = path
        fileNameLabel.stringValue = (path as NSString).lastPathComponent
        let url = URL(fileURLWithPath: path)
        let settings: [String: Any]
        if pendingFormat == "caf" {
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
            recordButton.title = "■ Stop"
            playButton.isEnabled = false  // Can't play during record.
            onStateChange?(true, false, 0, path)
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                let dur = rec.currentTime
                self.durationLabel.stringValue = Self.formatDuration(dur)
                self.onStateChange?(true, false, dur, self.lastOutputPath)
            }
        } catch {
            HypeLogger.shared.error(
                "AudioRecorder.start failed: \(error.localizedDescription)",
                source: "AudioRecorder"
            )
            isRecording = false
            dotView.isHidden = true
            recordButton.title = "● Record"
            onStateChange?(false, isPlaying, 0, "")
        }
    }

    // MARK: - Playback engine

    func play() {
        // Stop recording if running — can't play and record at once.
        if isRecording { stop() }

        guard !lastOutputPath.isEmpty,
              FileManager.default.fileExists(atPath: lastOutputPath) else {
            HypeLogger.shared.warn(
                "AudioRecorder.play: no file at '\(lastOutputPath)'",
                source: "AudioRecorder"
            )
            // Keep the document's audioPlaying flag honest — clear it.
            isPlaying = false
            onStateChange?(false, false, 0, lastOutputPath)
            return
        }

        let url = URL(fileURLWithPath: lastOutputPath)
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            let delegate = PlayerEndDelegate { [weak self] in
                guard let self = self else { return }
                self.isPlaying = false
                self.playButton.title = "▶ Play"
                self.onStateChange?(self.isRecording, false, p.duration, self.lastOutputPath)
            }
            p.delegate = delegate
            p.prepareToPlay()
            p.play()
            player = p
            playerDelegate = delegate
            isPlaying = true
            playButton.title = "■ Stop"
            onStateChange?(false, true, p.duration, lastOutputPath)
        } catch {
            HypeLogger.shared.error(
                "AudioRecorder.play failed for '\(lastOutputPath)': \(error.localizedDescription)",
                source: "AudioRecorder"
            )
            isPlaying = false
            playButton.title = "▶ Play"
            onStateChange?(isRecording, false, 0, lastOutputPath)
        }
    }

    func stopPlayback() {
        player?.stop()
        let dur = player?.currentTime ?? 0
        player = nil
        playerDelegate = nil
        isPlaying = false
        playButton.title = "▶ Play"
        onStateChange?(isRecording, false, dur, lastOutputPath)
    }

    // MARK: - Helpers

    private nonisolated static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Tiny delegate that just forwards the "playback finished" signal
/// to a closure. AVAudioPlayer requires the delegate to be an
/// NSObject conforming to AVAudioPlayerDelegate, and stuffing this
/// inside the host directly would force the host to inherit
/// NSObject which it already does (NSView), but making it a separate
/// class keeps the closure-based wiring tidy.
private final class PlayerEndDelegate: NSObject, AVAudioPlayerDelegate {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

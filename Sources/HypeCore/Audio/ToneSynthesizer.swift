import Foundation
import AVFoundation

/// Generates tone sequences using AVAudioEngine for melodic note playback.
/// Maps instrument names to waveform types for different timbres.
#if canImport(AppKit)
public final class ToneSynthesizer: @unchecked Sendable {

    public enum Waveform: Sendable {
        case sine       // smooth (flute)
        case sawtooth   // bright (harpsichord)
        case square     // hollow (boing)
        case triangle   // soft
    }

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var isPlayingFlag = false
    private var stopRequested = false

    public var isPlaying: Bool { isPlayingFlag }

    /// Map HyperCard instrument names to waveforms.
    public static func waveform(for instrument: String) -> Waveform {
        switch instrument.lowercased() {
        case "harpsichord": return .sawtooth
        case "flute":       return .sine
        case "boing":       return .square
        default:            return .sine
        }
    }

    /// Play a sequence of notes at the given tempo (BPM).
    public func playNotes(_ notes: [Note], tempo: Int, waveform: Waveform, completion: @escaping @Sendable () -> Void) {
        stop()
        guard !notes.isEmpty else { completion(); return }

        let sampleRate = 44100.0
        let bpm = Double(max(1, tempo))
        stopRequested = false
        isPlayingFlag = true

        // Pre-compute the entire sample buffer for all notes
        var allSamples: [Float] = []
        for note in notes {
            let durationSeconds = (NoteParser.durationInBeats(for: note) / bpm) * 60.0
            let sampleCount = Int(durationSeconds * sampleRate)
            let freq = NoteParser.frequency(for: note)

            for i in 0..<sampleCount {
                let t = Double(i) / sampleRate
                let phase = freq * t * 2.0 * .pi

                // Generate waveform sample
                var sample: Float
                if freq == 0 {
                    sample = 0 // rest
                } else {
                    switch waveform {
                    case .sine:
                        sample = Float(sin(phase))
                    case .sawtooth:
                        sample = Float(2.0 * (freq * t - floor(0.5 + freq * t)))
                    case .square:
                        sample = sin(phase) >= 0 ? 1.0 : -1.0
                    case .triangle:
                        sample = Float(2.0 * abs(2.0 * (freq * t - floor(freq * t + 0.5))) - 1.0)
                    }
                }

                // Simple ADSR envelope
                let progress = Double(i) / Double(max(1, sampleCount))
                let attackEnd = 0.02
                let releaseStart = 0.9
                let envelope: Float
                if progress < attackEnd {
                    envelope = Float(progress / attackEnd) // attack
                } else if progress > releaseStart {
                    envelope = Float((1.0 - progress) / (1.0 - releaseStart)) // release
                } else {
                    envelope = 0.8 // sustain
                }
                sample *= envelope * 0.3 // master volume
                allSamples.append(sample)
            }
        }

        // Create audio engine and source node
        let engine = AVAudioEngine()
        let totalSamples = allSamples.count
        var readIndex = 0

        let sourceNode = AVAudioSourceNode(format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            for frame in 0..<count {
                let value: Float
                if readIndex < totalSamples {
                    value = allSamples[readIndex]
                    readIndex += 1
                } else {
                    value = 0
                }
                for buffer in ablPointer {
                    let buf = UnsafeMutableBufferPointer<Float>(buffer)
                    buf[frame] = value
                }
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))

        self.engine = engine
        self.sourceNode = sourceNode

        do {
            try engine.start()
        } catch {
            isPlayingFlag = false
            completion()
            return
        }

        // Monitor playback completion on a background thread
        let totalDuration = Double(allSamples.count) / sampleRate
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + totalDuration + 0.1) { [weak self] in
            guard let self, !self.stopRequested else { return }
            self.stop()
            DispatchQueue.main.async { completion() }
        }
    }

    public func stop() {
        stopRequested = true
        engine?.stop()
        if let node = sourceNode {
            engine?.detach(node)
        }
        engine = nil
        sourceNode = nil
        isPlayingFlag = false
    }
}
#endif

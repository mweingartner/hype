import Foundation

#if canImport(AppKit) && canImport(AudioKit)
import AudioKit
import AudioToolbox
import AVFoundation

@MainActor
public final class AudioKitMusicProvider {
    public static let shared = AudioKitMusicProvider()

    private let engine = AudioEngine()
    private let mixer = Mixer(name: "HypeMusicMixer")
    private var samplers: [String: AppleSampler] = [:]
    private var tasks: [Task<Void, Never>] = []
    private var playbackToken = UUID()
    private var currentName: String?
    private var paused = false

    private let dlsURL = URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")

    public init() {
        engine.output = mixer
    }

    public var musicState: String {
        if paused { return "paused" }
        return currentName == nil ? "stopped" : "playing"
    }

    public func playNotes(instrument: String, noteString: String, tempo: Int) {
        let pattern = MusicPatternSpec.singleTrack(
            name: instrument,
            instrument: instrument,
            tempo: tempo,
            notes: noteString
        )
        playPattern(pattern, loop: false)
    }

    public func playPattern(_ pattern: MusicPatternSpec, loop: Bool? = nil) {
        stop()
        currentName = pattern.name
        paused = false
        playbackToken = UUID()
        ensureEngineStarted()
        schedule(pattern, token: playbackToken, loop: loop ?? pattern.loop)
    }

    public func stop() {
        playbackToken = UUID()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        for sampler in samplers.values {
            sampler.resetSampler()
        }
        engine.stop()
        currentName = nil
        paused = false
    }

    public func pause() {
        guard currentName != nil else { return }
        engine.pause()
        paused = true
    }

    public func resume() {
        guard currentName != nil else { return }
        ensureEngineStarted()
        paused = false
    }

    private func schedule(_ pattern: MusicPatternSpec, token: UUID, loop: Bool) {
        let tracks = pattern.tracks.isEmpty
            ? [MusicTrackSpec(name: "melody", instrument: "Acoustic Grand Piano", noteString: pattern.notes)]
            : pattern.tracks
        let duration = patternDuration(pattern)
        for track in tracks where !track.muted {
            let notes = NoteParser.parse(track.noteString.isEmpty ? pattern.notes : track.noteString)
            guard !notes.isEmpty else { continue }
            let descriptor = MusicInstrumentCatalog.resolve(track.instrument)
            let sampler = sampler(for: descriptor)
            let task = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.playTrack(notes: notes, track: track, sampler: sampler, tempo: pattern.tempo, token: token)
            }
            tasks.append(task)
        }
        let completion = Task { @MainActor [weak self] in
            guard let self else { return }
            guard await self.sleepForPlayback(seconds: duration, token: token) else { return }
            if loop {
                self.schedule(pattern, token: token, loop: true)
            } else {
                self.currentName = nil
                self.engine.stop()
            }
        }
        tasks.append(completion)
    }

    private func playTrack(
        notes: [Note],
        track: MusicTrackSpec,
        sampler: AppleSampler,
        tempo: Int,
        token: UUID
    ) async {
        let bpm = Double(max(1, tempo))
        for note in notes {
            guard playbackToken == token, !Task.isCancelled else { return }
            let duration = (NoteParser.durationInBeats(for: note) / bpm) * 60.0
            if let midi = NoteParser.midiNoteNumber(for: note) {
                sampler.volume = AUValue(track.volume)
                sampler.pan = AUValue(track.pan)
                sampler.play(noteNumber: MIDINoteNumber(midi), velocity: MIDIVelocity(100), channel: 0)
                guard await sleepForPlayback(seconds: duration, token: token) else {
                    sampler.stop(noteNumber: MIDINoteNumber(midi), channel: 0)
                    return
                }
                sampler.stop(noteNumber: MIDINoteNumber(midi), channel: 0)
            } else {
                guard await sleepForPlayback(seconds: duration, token: token) else { return }
            }
        }
    }

    private func sleepForPlayback(seconds: Double, token: UUID) async -> Bool {
        var remaining = max(0.01, seconds)
        let step = 0.02

        while remaining > 0 {
            guard playbackToken == token, !Task.isCancelled else { return false }
            if paused {
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                continue
            }

            let chunk = min(step, remaining)
            try? await Task.sleep(nanoseconds: UInt64(chunk * 1_000_000_000))
            if !paused {
                remaining -= chunk
            }
        }
        return playbackToken == token && !Task.isCancelled
    }

    private func sampler(for descriptor: MusicInstrumentDescriptor) -> AppleSampler {
        let key = "\(descriptor.isPercussion ? "p" : "m")\(descriptor.program)"
        if let sampler = samplers[key] {
            return sampler
        }
        let sampler = AppleSampler()
        let bank = descriptor.isPercussion ? kAUSampler_DefaultPercussionBankMSB : kAUSampler_DefaultMelodicBankMSB
        try? sampler.samplerUnit.loadSoundBankInstrument(
            at: dlsURL,
            program: UInt8(max(0, min(127, descriptor.program))),
            bankMSB: UInt8(bank),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        mixer.addInput(sampler)
        samplers[key] = sampler
        return sampler
    }

    private func ensureEngineStarted() {
        if engine.output == nil {
            engine.output = mixer
        }
        if !engine.avEngine.isRunning {
            try? engine.start()
        }
    }

    private func patternDuration(_ pattern: MusicPatternSpec) -> Double {
        let bpm = Double(max(1, pattern.tempo))
        let tracks = pattern.tracks.isEmpty
            ? [MusicTrackSpec(name: "melody", instrument: "Acoustic Grand Piano", noteString: pattern.notes)]
            : pattern.tracks
        let beats = tracks
            .map { track in
                NoteParser.parse(track.noteString.isEmpty ? pattern.notes : track.noteString)
                    .reduce(0.0) { $0 + NoteParser.durationInBeats(for: $1) }
            }
            .max() ?? 0
        return (beats / bpm) * 60.0
    }
}
#endif

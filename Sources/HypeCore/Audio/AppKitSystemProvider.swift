import Foundation

#if canImport(AppKit)
import AppKit

/// Production system provider for HypeTalk commands that touch local OS services.
///
/// `Interpreter` can run on cooperative executor threads, while `SoundPlayer`
/// is main-actor isolated because AppKit audio delegates can synchronously call
/// back on the invoking thread. Keep the actor hop here so every dispatch path
/// uses the same safe bridge.
public struct AppKitSystemProvider: SystemProvider, Sendable {
    public init() {}

    public func beep(count: Int) async {
        await MainActor.run {
            for _ in 0..<max(1, count) {
                NSSound.beep()
            }
        }
    }

    public func playSound(name: String, document: HypeDocument) async {
        await MainActor.run {
            SoundPlayer.shared.play(name: name, document: document)
        }
    }

    public func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument) async {
        await MainActor.run {
            SoundPlayer.shared.playNotes(instrument: instrument, noteString: noteString, tempo: tempo, document: document)
        }
    }

    public func playMusicPattern(_ pattern: MusicPatternSpec, loop: Bool, document: HypeDocument) async {
        await MainActor.run {
            #if canImport(AudioKit)
            AudioKitMusicProvider.shared.playPattern(pattern, loop: loop)
            #else
            SoundPlayer.shared.playNotes(
                instrument: pattern.tracks.first?.instrument ?? "Acoustic Grand Piano",
                noteString: pattern.tracks.first?.noteString ?? pattern.notes,
                tempo: pattern.tempo,
                document: document
            )
            #endif
        }
    }

    public func stopSound() async {
        await MainActor.run {
            SoundPlayer.shared.stop()
        }
    }

    public func stopMusic() async {
        await MainActor.run {
            #if canImport(AudioKit)
            AudioKitMusicProvider.shared.stop()
            #else
            SoundPlayer.shared.stop()
            #endif
        }
    }

    public func pauseMusic() async {
        await MainActor.run {
            #if canImport(AudioKit)
            AudioKitMusicProvider.shared.pause()
            #endif
        }
    }

    public func resumeMusic() async {
        await MainActor.run {
            #if canImport(AudioKit)
            AudioKitMusicProvider.shared.resume()
            #endif
        }
    }

    public func currentSoundName() async -> String {
        await MainActor.run {
            SoundPlayer.shared.soundName
        }
    }

    public func currentMusicState() async -> String {
        await MainActor.run {
            #if canImport(AudioKit)
            AudioKitMusicProvider.shared.musicState
            #else
            SoundPlayer.shared.soundName == "done" ? "stopped" : "playing"
            #endif
        }
    }
}
#endif

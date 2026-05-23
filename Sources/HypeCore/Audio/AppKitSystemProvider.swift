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

    public func stopSound() async {
        await MainActor.run {
            SoundPlayer.shared.stop()
        }
    }

    public func currentSoundName() async -> String {
        await MainActor.run {
            SoundPlayer.shared.soundName
        }
    }
}
#endif

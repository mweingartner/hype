import Foundation
#if canImport(AppKit)
import AppKit
import AVFoundation

/// Singleton sound player for HypeTalk `play` and `beep` commands.
///
/// Wraps `NSSound` for `.aiff`/`.wav`/`.caf` playback and
/// `AVAudioPlayer` for `.m4r` (MPEG-4 ringtone) playback —
/// `NSSound` can't play `.m4r` files, which is the format used by
/// the macOS ToneLibrary alert tones and ringtones (e.g. "Sonar",
/// "Pebble", "Chime"). `ToneSynthesizer` handles melodic note
/// sequences.
public final class SoundPlayer: NSObject, NSSoundDelegate {

    nonisolated(unsafe) public static let shared = SoundPlayer()

    private var currentSound: NSSound?
    private var avPlayer: AVAudioPlayer?
    private var currentName: String?
    private var toneSynth: ToneSynthesizer?

    /// HyperCard built-in sound names mapped to macOS system sounds.
    private static let hyperCardSounds: [String: String] = [
        "boing": "Frog",
        "harpsichord": "Hero",
        "flute": "Purr",
    ]

    /// All macOS system alert sound names (sans extension) from
    /// `/System/Library/Sounds/`.
    public static let systemSoundNames: [String] = {
        let dir = "/System/Library/Sounds"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return files.compactMap { $0.hasSuffix(".aiff") ? String($0.dropLast(5)) : nil }.sorted()
    }()

    /// Directories searched for macOS alert tones and ringtones
    /// (the modern sounds visible in System Settings → Sound →
    /// Alert sound, like "Sonar", "Breeze", "Pebble", etc.).
    /// These are stored as `.m4r` or `.caf` files inside the
    /// ToneLibrary private framework.
    private static let toneLibraryDirs: [String] = [
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones",
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones",
        // Fallback for future macOS layouts:
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Resources/AlertTones",
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Resources/Ringtones",
    ]

    /// Lazily built lookup table mapping lowercased sound names to
    /// file paths. Scans the ToneLibrary directories once and
    /// caches the result. Handles both flat filenames ("Sonar.m4r")
    /// and subdirectory-qualified names ("Classic/Chime.m4r",
    /// "EncoreInfinitum/Antic-EncoreInfinitum.caf").
    ///
    /// The lookup key is the human-readable name derived from the
    /// filename: strip the extension, strip any "-SubfolderName"
    /// suffix (e.g. "Antic-EncoreInfinitum.caf" → "Antic"), and
    /// lowercase. When multiple files map to the same key, the
    /// first one found wins.
    private static let toneLibraryIndex: [String: URL] = {
        var index: [String: URL] = [:]
        let fm = FileManager.default
        for dir in toneLibraryDirs {
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "m4r" || ext == "caf" || ext == "aiff" || ext == "wav" else { continue }
                // Derive the human-readable name:
                //   "Antic-EncoreInfinitum.caf" → "antic"
                //   "Sonar.m4r"                 → "sonar"
                //   "Choo Choo.m4r"             → "choo choo"
                var stem = url.deletingPathExtension().lastPathComponent
                // Strip "-SubfolderName" suffixes (ToneLibrary convention)
                if let dashRange = stem.range(of: "-", options: .backwards) {
                    let suffix = String(stem[dashRange.upperBound...])
                    // Only strip if the suffix matches a known subfolder
                    let parentDir = url.deletingLastPathComponent().lastPathComponent
                    if suffix == parentDir {
                        stem = String(stem[..<dashRange.lowerBound])
                    }
                }
                let key = stem.lowercased()
                if index[key] == nil {
                    index[key] = url
                }
            }
        }
        return index
    }()

    // MARK: - Simple sound playback

    /// Play a sound by name. Resolution order:
    ///
    /// 1. macOS system alert sounds (`/System/Library/Sounds/`)
    ///    via `NSSound(named:)` — handles Basso, Blow, Bottle,
    ///    Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr,
    ///    Sosumi, Submarine, Tink.
    ///
    /// 2. macOS ToneLibrary alert tones and ringtones — handles
    ///    modern sounds like Sonar, Pebble, Chime, Breeze, Aurora,
    ///    Bamboo, etc. Played via `AVAudioPlayer` (since
    ///    `NSSound` can't open `.m4r` files).
    ///
    /// 3. HyperCard built-in name → system sound mapping
    ///    ("boing"→Frog, "harpsichord"→Hero, "flute"→Purr).
    ///
    /// 4. SpriteRepository `.audioClip` asset by name.
    ///
    /// 5. File path fallback.
    public func play(name: String, document: HypeDocument? = nil) {
        stop()
        currentName = name

        // 1. System alert sounds (NSSound searches /System/Library/Sounds,
        //    /Library/Sounds, and ~/Library/Sounds automatically)
        if let sysSound = NSSound(named: NSSound.Name(name)) {
            sysSound.delegate = self
            currentSound = sysSound
            sysSound.play()
            return
        }

        // 2. ToneLibrary alert tones and ringtones (case-insensitive)
        if let url = Self.toneLibraryIndex[name.lowercased()] {
            if playWithAVAudioPlayer(url: url) { return }
        }

        // 3. HyperCard built-in mapping
        if let mapped = Self.hyperCardSounds[name.lowercased()],
           let sysSound = NSSound(named: NSSound.Name(mapped)) {
            sysSound.delegate = self
            currentSound = sysSound
            sysSound.play()
            return
        }

        // 4. SpriteRepository audio asset
        if let doc = document,
           let asset = doc.spriteRepository.assets.first(where: {
               $0.name.lowercased() == name.lowercased() && $0.kind == .audioClip
           }) {
            let tempDir = FileManager.default.temporaryDirectory
            let ext: String
            switch asset.mimeType {
            case "audio/mpeg": ext = "mp3"
            case "audio/wav":  ext = "wav"
            case "audio/aiff": ext = "aiff"
            case "audio/mp4":  ext = "m4a"
            case "audio/x-caf": ext = "caf"
            default: ext = "aiff"
            }
            let tempFile = tempDir.appendingPathComponent("\(asset.id.uuidString).\(ext)")
            if !FileManager.default.fileExists(atPath: tempFile.path) {
                try? asset.data.write(to: tempFile)
            }
            if let sound = NSSound(contentsOf: tempFile, byReference: false) {
                sound.delegate = self
                currentSound = sound
                sound.play()
                return
            }
            // NSSound may fail on .m4r/.mp3 — fall back to AVAudioPlayer
            if playWithAVAudioPlayer(url: tempFile) { return }
        }

        // 5. File path fallback
        let url = URL(fileURLWithPath: name)
        if FileManager.default.fileExists(atPath: url.path) {
            if let sound = NSSound(contentsOf: url, byReference: false) {
                sound.delegate = self
                currentSound = sound
                sound.play()
                return
            }
            // Try AVAudioPlayer for formats NSSound doesn't support
            if playWithAVAudioPlayer(url: url) { return }
        }

        // Couldn't load — clear state
        currentName = nil
    }

    /// Play a file via `AVAudioPlayer`. Returns true on success.
    /// Used for `.m4r` and other formats that `NSSound` can't handle.
    @discardableResult
    private func playWithAVAudioPlayer(url: URL) -> Bool {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            avPlayer = player
            player.play()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Note sequence playback

    /// Play a melody using tone synthesis.
    public func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument? = nil) {
        stop()
        currentName = instrument

        let notes = NoteParser.parse(noteString)
        guard !notes.isEmpty else { currentName = nil; return }

        let waveform = ToneSynthesizer.waveform(for: instrument)
        let synth = ToneSynthesizer()
        toneSynth = synth

        synth.playNotes(notes, tempo: tempo, waveform: waveform) { [weak self] in
            self?.currentName = nil
            self?.toneSynth = nil
        }
    }

    // MARK: - Control

    public func stop() {
        currentSound?.stop()
        currentSound = nil
        avPlayer?.stop()
        avPlayer = nil
        toneSynth?.stop()
        toneSynth = nil
        currentName = nil
    }

    /// Returns "done" when no sound is playing, or the name of the current sound.
    public var soundName: String {
        if let name = currentName, isPlaying {
            return name
        }
        return "done"
    }

    public var isPlaying: Bool {
        if let sound = currentSound, sound.isPlaying { return true }
        if let player = avPlayer, player.isPlaying { return true }
        if let synth = toneSynth, synth.isPlaying { return true }
        return false
    }

    // MARK: - NSSoundDelegate

    public func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        if currentSound === sound {
            currentSound = nil
            currentName = nil
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension SoundPlayer: AVAudioPlayerDelegate {
    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if avPlayer === player {
            avPlayer = nil
            currentName = nil
        }
    }
}
#endif

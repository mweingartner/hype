import Foundation

/// A single parsed note from a HyperCard NAOD note string.
public struct Note: Sendable, Equatable {
    public enum Name: String, Sendable, CaseIterable {
        case c, d, e, f, g, a, b, r  // r = rest
    }
    public enum Accidental: Sendable { case natural, sharp, flat }
    public enum Duration: String, Sendable, CaseIterable {
        case whole = "w"       // 4 beats
        case half = "h"        // 2 beats
        case quarter = "q"     // 1 beat
        case eighth = "e"      // 0.5 beats
        case sixteenth = "s"   // 0.25 beats
        case thirtySecond = "t" // 0.125 beats
        case sixtyFourth = "x" // 0.0625 beats
    }

    public var name: Name
    public var accidental: Accidental
    public var octave: Int
    public var duration: Duration
    public var dotted: Bool
    public var triplet: Bool

    public init(name: Name, accidental: Accidental = .natural, octave: Int = 4,
                duration: Duration = .quarter, dotted: Bool = false, triplet: Bool = false) {
        self.name = name; self.accidental = accidental; self.octave = octave
        self.duration = duration; self.dotted = dotted; self.triplet = triplet
    }
}

/// Parses HyperCard NAOD (Name-Accidental-Octave-Duration) note strings.
public enum NoteParser {

    /// Parse a space-separated note string into individual Note values.
    /// Tracks sticky defaults for octave and duration (carry forward from
    /// previous note, matching HyperCard behavior).
    public static func parse(_ noteString: String) -> [Note] {
        let tokens = noteString.split(separator: " ", omittingEmptySubsequences: true)
        var notes: [Note] = []
        var lastOctave = 4
        var lastDuration = Note.Duration.quarter

        for token in tokens {
            if let note = parseToken(String(token), lastOctave: lastOctave, lastDuration: lastDuration) {
                lastOctave = note.octave
                lastDuration = note.duration
                notes.append(note)
            }
        }
        return notes
    }

    private static func parseToken(_ token: String, lastOctave: Int, lastDuration: Note.Duration) -> Note? {
        let chars = Array(token.lowercased())
        guard !chars.isEmpty else { return nil }
        var idx = 0

        // 1. Note name (required)
        guard let name = Note.Name(rawValue: String(chars[idx])) else { return nil }
        idx += 1

        // 2. Accidental (optional)
        var accidental = Note.Accidental.natural
        if idx < chars.count {
            if chars[idx] == "#" { accidental = .sharp; idx += 1 }
            else if chars[idx] == "b" && name != .b {
                // "b" after a note name = flat (but not after "b" itself which IS the note name)
                accidental = .flat; idx += 1
            }
        }

        // 3. Octave (optional digits)
        var octave = lastOctave
        var octaveStr = ""
        while idx < chars.count && chars[idx].isNumber {
            octaveStr.append(chars[idx]); idx += 1
        }
        if !octaveStr.isEmpty, let o = Int(octaveStr) { octave = o }

        // 4. Duration (optional letter)
        var duration = lastDuration
        if idx < chars.count, let d = Note.Duration(rawValue: String(chars[idx])) {
            duration = d; idx += 1
        }

        // 5. Dotted (optional ".")
        var dotted = false
        if idx < chars.count && chars[idx] == "." { dotted = true; idx += 1 }

        // 6. Triplet (optional "3")
        var triplet = false
        if idx < chars.count && chars[idx] == "3" { triplet = true; idx += 1 }

        return Note(name: name, accidental: accidental, octave: octave,
                    duration: duration, dotted: dotted, triplet: triplet)
    }

    /// Calculate the frequency in Hz for a note using equal temperament (A4 = 440Hz).
    public static func frequency(for note: Note) -> Double {
        guard note.name != .r else { return 0 } // rest = silence
        // Semitone offsets from C in each octave
        let semitones: [Note.Name: Int] = [.c: 0, .d: 2, .e: 4, .f: 5, .g: 7, .a: 9, .b: 11, .r: 0]
        var semitone = semitones[note.name]! + (note.octave - 4) * 12
        switch note.accidental {
        case .sharp: semitone += 1
        case .flat:  semitone -= 1
        case .natural: break
        }
        // A4 is 9 semitones above C4, so offset from A4 is (semitone - 9)
        let offsetFromA4 = Double(semitone - 9)
        return 440.0 * pow(2.0, offsetFromA4 / 12.0)
    }

    /// MIDI note number for equal-tempered playback engines.
    /// Middle C (C4) is 60. Rests return nil.
    public static func midiNoteNumber(for note: Note) -> Int? {
        guard note.name != .r else { return nil }
        let semitones: [Note.Name: Int] = [.c: 0, .d: 2, .e: 4, .f: 5, .g: 7, .a: 9, .b: 11, .r: 0]
        var semitone = semitones[note.name]! + (note.octave + 1) * 12
        switch note.accidental {
        case .sharp: semitone += 1
        case .flat: semitone -= 1
        case .natural: break
        }
        return min(127, max(0, semitone))
    }

    /// Duration in beats (quarter note = 1.0 beat).
    public static func durationInBeats(for note: Note) -> Double {
        let base: Double
        switch note.duration {
        case .whole:        base = 4.0
        case .half:         base = 2.0
        case .quarter:      base = 1.0
        case .eighth:       base = 0.5
        case .sixteenth:    base = 0.25
        case .thirtySecond: base = 0.125
        case .sixtyFourth:  base = 0.0625
        }
        var result = base
        if note.dotted { result *= 1.5 }
        if note.triplet { result *= 2.0 / 3.0 }
        return result
    }
}

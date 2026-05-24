import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public struct MusicLibrary: Codable, Sendable, Equatable {
    public var patterns: [MusicPatternSpec]

    public init(patterns: [MusicPatternSpec] = []) {
        self.patterns = patterns
    }

    public func pattern(named name: String) -> MusicPatternSpec? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return patterns.reversed().first { $0.name.lowercased() == needle }
    }

    public mutating func upsertPattern(_ pattern: MusicPatternSpec) {
        if let index = patterns.firstIndex(where: { $0.name.caseInsensitiveCompare(pattern.name) == .orderedSame }) {
            patterns[index] = pattern
        } else {
            patterns.append(pattern)
        }
    }
}

public struct MusicPatternSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var tempo: Int
    public var timeSignature: String
    public var loop: Bool
    public var tracks: [MusicTrackSpec]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String,
        tempo: Int = 120,
        timeSignature: String = "4/4",
        loop: Bool = false,
        tracks: [MusicTrackSpec] = [],
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.tempo = max(1, tempo)
        self.timeSignature = timeSignature
        self.loop = loop
        self.tracks = tracks
        self.notes = notes
    }

    public static func singleTrack(
        name: String,
        instrument: String,
        tempo: Int,
        notes: String,
        loop: Bool = false
    ) -> MusicPatternSpec {
        MusicPatternSpec(
            name: name,
            tempo: tempo,
            loop: loop,
            tracks: [
                MusicTrackSpec(
                    name: "melody",
                    instrument: instrument,
                    noteString: notes
                ),
            ],
            notes: notes
        )
    }
}

public struct MusicTrackSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var instrument: String
    public var noteString: String
    public var volume: Double
    public var pan: Double
    public var muted: Bool
    public var solo: Bool
    public var effects: [MusicEffectSpec]

    public init(
        id: UUID = UUID(),
        name: String,
        instrument: String = "Acoustic Grand Piano",
        noteString: String = "",
        volume: Double = 1,
        pan: Double = 0,
        muted: Bool = false,
        solo: Bool = false,
        effects: [MusicEffectSpec] = []
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.noteString = noteString
        self.volume = min(1, max(0, volume))
        self.pan = min(1, max(-1, pan))
        self.muted = muted
        self.solo = solo
        self.effects = effects
    }
}

public struct MusicEffectSpec: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var kind: String
    public var amount: Double

    public init(id: UUID = UUID(), kind: String, amount: Double = 0) {
        self.id = id
        self.kind = kind
        self.amount = min(1, max(0, amount))
    }
}

public struct MusicInstrumentDescriptor: Identifiable, Codable, Sendable, Equatable {
    public var id: Int { program }
    public var program: Int
    public var name: String
    public var family: String
    public var isPercussion: Bool

    public init(program: Int, name: String, family: String, isPercussion: Bool = false) {
        self.program = program
        self.name = name
        self.family = family
        self.isPercussion = isPercussion
    }
}

public enum MusicInstrumentCatalog {
    public static let instruments: [MusicInstrumentDescriptor] = [
        MusicInstrumentDescriptor(program: 0, name: "Acoustic Grand Piano", family: "Piano"),
        MusicInstrumentDescriptor(program: 1, name: "Bright Acoustic Piano", family: "Piano"),
        MusicInstrumentDescriptor(program: 2, name: "Electric Grand Piano", family: "Piano"),
        MusicInstrumentDescriptor(program: 3, name: "Honky-tonk Piano", family: "Piano"),
        MusicInstrumentDescriptor(program: 4, name: "Electric Piano 1", family: "Piano"),
        MusicInstrumentDescriptor(program: 5, name: "Electric Piano 2", family: "Piano"),
        MusicInstrumentDescriptor(program: 6, name: "Harpsichord", family: "Piano"),
        MusicInstrumentDescriptor(program: 7, name: "Clavi", family: "Piano"),
        MusicInstrumentDescriptor(program: 8, name: "Celesta", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 9, name: "Glockenspiel", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 10, name: "Music Box", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 11, name: "Vibraphone", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 12, name: "Marimba", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 13, name: "Xylophone", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 14, name: "Tubular Bells", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 15, name: "Dulcimer", family: "Chromatic Percussion"),
        MusicInstrumentDescriptor(program: 16, name: "Drawbar Organ", family: "Organ"),
        MusicInstrumentDescriptor(program: 17, name: "Percussive Organ", family: "Organ"),
        MusicInstrumentDescriptor(program: 18, name: "Rock Organ", family: "Organ"),
        MusicInstrumentDescriptor(program: 19, name: "Church Organ", family: "Organ"),
        MusicInstrumentDescriptor(program: 20, name: "Reed Organ", family: "Organ"),
        MusicInstrumentDescriptor(program: 21, name: "Accordion", family: "Organ"),
        MusicInstrumentDescriptor(program: 22, name: "Harmonica", family: "Organ"),
        MusicInstrumentDescriptor(program: 23, name: "Tango Accordion", family: "Organ"),
        MusicInstrumentDescriptor(program: 24, name: "Acoustic Guitar Nylon", family: "Guitar"),
        MusicInstrumentDescriptor(program: 25, name: "Acoustic Guitar Steel", family: "Guitar"),
        MusicInstrumentDescriptor(program: 26, name: "Electric Guitar Jazz", family: "Guitar"),
        MusicInstrumentDescriptor(program: 27, name: "Electric Guitar Clean", family: "Guitar"),
        MusicInstrumentDescriptor(program: 28, name: "Electric Guitar Muted", family: "Guitar"),
        MusicInstrumentDescriptor(program: 29, name: "Overdriven Guitar", family: "Guitar"),
        MusicInstrumentDescriptor(program: 30, name: "Distortion Guitar", family: "Guitar"),
        MusicInstrumentDescriptor(program: 31, name: "Guitar Harmonics", family: "Guitar"),
        MusicInstrumentDescriptor(program: 32, name: "Acoustic Bass", family: "Bass"),
        MusicInstrumentDescriptor(program: 33, name: "Electric Bass Finger", family: "Bass"),
        MusicInstrumentDescriptor(program: 34, name: "Electric Bass Pick", family: "Bass"),
        MusicInstrumentDescriptor(program: 35, name: "Fretless Bass", family: "Bass"),
        MusicInstrumentDescriptor(program: 36, name: "Slap Bass 1", family: "Bass"),
        MusicInstrumentDescriptor(program: 37, name: "Slap Bass 2", family: "Bass"),
        MusicInstrumentDescriptor(program: 38, name: "Synth Bass 1", family: "Bass"),
        MusicInstrumentDescriptor(program: 39, name: "Synth Bass 2", family: "Bass"),
        MusicInstrumentDescriptor(program: 40, name: "Violin", family: "Strings"),
        MusicInstrumentDescriptor(program: 41, name: "Viola", family: "Strings"),
        MusicInstrumentDescriptor(program: 42, name: "Cello", family: "Strings"),
        MusicInstrumentDescriptor(program: 43, name: "Contrabass", family: "Strings"),
        MusicInstrumentDescriptor(program: 44, name: "Tremolo Strings", family: "Strings"),
        MusicInstrumentDescriptor(program: 45, name: "Pizzicato Strings", family: "Strings"),
        MusicInstrumentDescriptor(program: 46, name: "Orchestral Harp", family: "Strings"),
        MusicInstrumentDescriptor(program: 47, name: "Timpani", family: "Strings"),
        MusicInstrumentDescriptor(program: 48, name: "String Ensemble 1", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 49, name: "String Ensemble 2", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 50, name: "SynthStrings 1", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 51, name: "SynthStrings 2", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 52, name: "Choir Aahs", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 53, name: "Voice Oohs", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 54, name: "Synth Voice", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 55, name: "Orchestra Hit", family: "Ensemble"),
        MusicInstrumentDescriptor(program: 56, name: "Trumpet", family: "Brass"),
        MusicInstrumentDescriptor(program: 57, name: "Trombone", family: "Brass"),
        MusicInstrumentDescriptor(program: 58, name: "Tuba", family: "Brass"),
        MusicInstrumentDescriptor(program: 59, name: "Muted Trumpet", family: "Brass"),
        MusicInstrumentDescriptor(program: 60, name: "French Horn", family: "Brass"),
        MusicInstrumentDescriptor(program: 61, name: "Brass Section", family: "Brass"),
        MusicInstrumentDescriptor(program: 62, name: "SynthBrass 1", family: "Brass"),
        MusicInstrumentDescriptor(program: 63, name: "SynthBrass 2", family: "Brass"),
        MusicInstrumentDescriptor(program: 64, name: "Soprano Sax", family: "Reed"),
        MusicInstrumentDescriptor(program: 65, name: "Alto Sax", family: "Reed"),
        MusicInstrumentDescriptor(program: 66, name: "Tenor Sax", family: "Reed"),
        MusicInstrumentDescriptor(program: 67, name: "Baritone Sax", family: "Reed"),
        MusicInstrumentDescriptor(program: 68, name: "Oboe", family: "Reed"),
        MusicInstrumentDescriptor(program: 69, name: "English Horn", family: "Reed"),
        MusicInstrumentDescriptor(program: 70, name: "Bassoon", family: "Reed"),
        MusicInstrumentDescriptor(program: 71, name: "Clarinet", family: "Reed"),
        MusicInstrumentDescriptor(program: 72, name: "Piccolo", family: "Pipe"),
        MusicInstrumentDescriptor(program: 73, name: "Flute", family: "Pipe"),
        MusicInstrumentDescriptor(program: 74, name: "Recorder", family: "Pipe"),
        MusicInstrumentDescriptor(program: 75, name: "Pan Flute", family: "Pipe"),
        MusicInstrumentDescriptor(program: 76, name: "Blown Bottle", family: "Pipe"),
        MusicInstrumentDescriptor(program: 77, name: "Shakuhachi", family: "Pipe"),
        MusicInstrumentDescriptor(program: 78, name: "Whistle", family: "Pipe"),
        MusicInstrumentDescriptor(program: 79, name: "Ocarina", family: "Pipe"),
        MusicInstrumentDescriptor(program: 80, name: "Lead 1 Square", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 81, name: "Lead 2 Sawtooth", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 82, name: "Lead 3 Calliope", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 83, name: "Lead 4 Chiff", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 84, name: "Lead 5 Charang", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 85, name: "Lead 6 Voice", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 86, name: "Lead 7 Fifths", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 87, name: "Lead 8 Bass + Lead", family: "Synth Lead"),
        MusicInstrumentDescriptor(program: 88, name: "Pad 1 New Age", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 89, name: "Pad 2 Warm", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 90, name: "Pad 3 Polysynth", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 91, name: "Pad 4 Choir", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 92, name: "Pad 5 Bowed", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 93, name: "Pad 6 Metallic", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 94, name: "Pad 7 Halo", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 95, name: "Pad 8 Sweep", family: "Synth Pad"),
        MusicInstrumentDescriptor(program: 96, name: "FX 1 Rain", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 97, name: "FX 2 Soundtrack", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 98, name: "FX 3 Crystal", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 99, name: "FX 4 Atmosphere", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 100, name: "FX 5 Brightness", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 101, name: "FX 6 Goblins", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 102, name: "FX 7 Echoes", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 103, name: "FX 8 Sci-fi", family: "Synth Effects"),
        MusicInstrumentDescriptor(program: 104, name: "Sitar", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 105, name: "Banjo", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 106, name: "Shamisen", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 107, name: "Koto", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 108, name: "Kalimba", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 109, name: "Bag Pipe", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 110, name: "Fiddle", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 111, name: "Shanai", family: "Ethnic"),
        MusicInstrumentDescriptor(program: 112, name: "Tinkle Bell", family: "Percussive"),
        MusicInstrumentDescriptor(program: 113, name: "Agogo", family: "Percussive"),
        MusicInstrumentDescriptor(program: 114, name: "Steel Drums", family: "Percussive"),
        MusicInstrumentDescriptor(program: 115, name: "Woodblock", family: "Percussive"),
        MusicInstrumentDescriptor(program: 116, name: "Taiko Drum", family: "Percussive"),
        MusicInstrumentDescriptor(program: 117, name: "Melodic Tom", family: "Percussive"),
        MusicInstrumentDescriptor(program: 118, name: "Synth Drum", family: "Percussive"),
        MusicInstrumentDescriptor(program: 119, name: "Reverse Cymbal", family: "Percussive"),
        MusicInstrumentDescriptor(program: 120, name: "Guitar Fret Noise", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 121, name: "Breath Noise", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 122, name: "Seashore", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 123, name: "Bird Tweet", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 124, name: "Telephone Ring", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 125, name: "Helicopter", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 126, name: "Applause", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 127, name: "Gunshot", family: "Sound Effects"),
        MusicInstrumentDescriptor(program: 0, name: "Standard Drum Kit", family: "Drums", isPercussion: true),
    ]

    public static func resolve(_ rawName: String) -> MusicInstrumentDescriptor {
        let normalizedName = normalized(rawName)
        if let descriptor = instruments.first(where: { normalized($0.name) == normalizedName }) {
            return descriptor
        }
        if let alias = aliases[normalizedName],
           let descriptor = instruments.first(where: { normalized($0.name) == alias }) {
            return descriptor
        }
        return instruments[0]
    }

    public static var displayList: String {
        instruments
            .map { $0.isPercussion ? "\($0.name) (drums)" : "\($0.name) [\($0.family)]" }
            .joined(separator: "\n")
    }

    public static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static let aliases: [String: String] = [
        "piano": "acousticgrandpiano",
        "grandpiano": "acousticgrandpiano",
        "electricpiano": "electricpiano1",
        "epiano": "electricpiano1",
        "harpsichord": "harpsichord",
        "clav": "clavi",
        "clavinet": "clavi",
        "organ": "drawbarorgan",
        "guitar": "acousticguitarsteel",
        "bass": "electricbassfinger",
        "strings": "stringensemble1",
        "stringsection": "stringensemble1",
        "synthstrings": "synthstrings1",
        "choir": "choiraahs",
        "voice": "voiceoohs",
        "brass": "brasssection",
        "sax": "altosax",
        "saxophone": "altosax",
        "flute": "flute",
        "lead": "lead2sawtooth",
        "synthlead": "lead2sawtooth",
        "pad": "pad2warm",
        "synthpad": "pad2warm",
        "fx": "fx3crystal",
        "drums": "standarddrumkit",
        "drumkit": "standarddrumkit",
        "percussion": "standarddrumkit",
        "boing": "synthdrum",
    ]
}

#if canImport(CoreGraphics)
public struct MusicControlPlaybackRequest: Sendable, Equatable {
    public var pattern: MusicPatternSpec
    public var loop: Bool
    public var triggerIdentifier: String?

    public init(pattern: MusicPatternSpec, loop: Bool = false, triggerIdentifier: String? = nil) {
        self.pattern = pattern
        self.loop = loop
        self.triggerIdentifier = triggerIdentifier
    }
}

public enum MusicControlInteraction {
    public static let stepSequencerColumnCount = 16
    public static let stepSequencerRowCount = 4

    private static let whiteNotes = [
        "c4", "d4", "e4", "f4", "g4", "a4", "b4",
        "c5", "d5", "e5", "f5", "g5", "a5", "b5",
    ]

    private static let blackNotes: [(whiteIndex: Int, note: String)] = [
        (0, "c#4"), (1, "d#4"), (3, "f#4"), (4, "g#4"), (5, "a#4"),
        (7, "c#5"), (8, "d#5"), (10, "f#5"), (11, "g#5"), (12, "a#5"),
    ]

    private static let defaultStepNotesByRow = [
        ["c5", "d5", "e5", "g5", "a5", "g5", "e5", "d5", "c5", "e5", "g5", "a5", "g5", "e5", "d5", "c5"],
        ["g4", "a4", "b4", "d5", "e5", "d5", "b4", "a4", "g4", "b4", "d5", "e5", "d5", "b4", "a4", "g4"],
        ["e4", "f4", "g4", "b4", "c5", "b4", "g4", "f4", "e4", "g4", "b4", "c5", "b4", "g4", "f4", "e4"],
        ["c4", "d4", "e4", "g4", "a4", "g4", "e4", "d4", "c4", "e4", "g4", "a4", "g4", "e4", "d4", "c4"],
    ]

    public static func playbackRequest(
        for part: Part,
        document: HypeDocument,
        clickPoint: CGPoint
    ) -> MusicControlPlaybackRequest? {
        switch part.partType {
        case .pianoKeyboard:
            if let note = keyboardNote(at: clickPoint, in: rect(for: part)) {
                return MusicControlPlaybackRequest(
                    pattern: singleNotePattern(for: part, note: note),
                    triggerIdentifier: "keyboard:\(part.id.uuidString):\(note)"
                )
            }
            return boundPatternRequest(for: part, document: document)
        case .stepSequencer:
            if let cell = stepSequencerCell(at: clickPoint, in: rect(for: part)) {
                return stepSequencerRequest(for: part, document: document, cell: cell)
            }
            return boundPatternRequest(for: part, document: document) ?? demoPatternRequest(for: part)
        case .musicPlayer, .musicMixer:
            return boundPatternRequest(for: part, document: document) ?? demoPatternRequest(for: part)
        default:
            return nil
        }
    }

    public static func keyboardRect(in partRect: CGRect) -> CGRect {
        partRect.insetBy(dx: 12, dy: 44)
    }

    public static func stepSequencerGridRect(in partRect: CGRect) -> CGRect {
        partRect.insetBy(dx: 12, dy: 44)
    }

    public static func keyboardNote(at point: CGPoint, in partRect: CGRect) -> String? {
        let keyboard = keyboardRect(in: partRect)
        guard keyboard.width > 20, keyboard.height > 18, keyboard.contains(point) else {
            return nil
        }

        let keyWidth = keyboard.width / CGFloat(whiteNotes.count)
        for item in blackNotes {
            let key = CGRect(
                x: keyboard.minX + CGFloat(item.whiteIndex + 1) * keyWidth - keyWidth * 0.28,
                y: keyboard.minY,
                width: keyWidth * 0.56,
                height: keyboard.height * 0.62
            )
            if key.contains(point) {
                return item.note
            }
        }

        let rawIndex = Int((point.x - keyboard.minX) / keyWidth)
        let index = min(whiteNotes.count - 1, max(0, rawIndex))
        return whiteNotes[index]
    }

    public static func stepSequencerCell(at point: CGPoint, in partRect: CGRect) -> (row: Int, column: Int)? {
        let grid = stepSequencerGridRect(in: partRect)
        guard grid.width > 20, grid.height > 18, grid.contains(point) else {
            return nil
        }

        let cellWidth = grid.width / CGFloat(stepSequencerColumnCount)
        let cellHeight = grid.height / CGFloat(stepSequencerRowCount)
        let column = min(stepSequencerColumnCount - 1, max(0, Int((point.x - grid.minX) / cellWidth)))
        let row = min(stepSequencerRowCount - 1, max(0, Int((point.y - grid.minY) / cellHeight)))
        return (row, column)
    }

    private static func rect(for part: Part) -> CGRect {
        CGRect(x: part.left, y: part.top, width: part.width, height: part.height)
    }

    private static func boundPatternRequest(for part: Part, document: HypeDocument) -> MusicControlPlaybackRequest? {
        guard !part.musicPatternName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let pattern = document.musicLibrary.pattern(named: part.musicPatternName) else {
            return nil
        }
        return MusicControlPlaybackRequest(pattern: pattern, loop: part.musicLoop || pattern.loop)
    }

    private struct StepNoteSelection {
        var token: String
        var instrument: String
        var tempo: Int
        var volume: Double
    }

    private static func singleNotePattern(for part: Part, note: String) -> MusicPatternSpec {
        let noteString = "\(note)e"
        let instrument = MusicInstrumentCatalog.resolve(part.musicInstrumentName).name
        return MusicPatternSpec(
            name: "\(part.name) \(note.uppercased())",
            tempo: max(1, Int(part.musicTempo.rounded())),
            tracks: [
                MusicTrackSpec(
                    name: "keyboard",
                    instrument: instrument,
                    noteString: noteString,
                    volume: part.musicVolume
                ),
            ],
            notes: noteString
        )
    }

    private static func stepSequencerRequest(
        for part: Part,
        document: HypeDocument,
        cell: (row: Int, column: Int)
    ) -> MusicControlPlaybackRequest {
        let selection = stepNoteSelection(for: part, document: document, cell: cell)
        let pattern = MusicPatternSpec(
            name: "\(part.name) Step \(cell.column + 1), Row \(cell.row + 1)",
            tempo: selection.tempo,
            tracks: [
                MusicTrackSpec(
                    name: "step \(cell.column + 1)",
                    instrument: selection.instrument,
                    noteString: selection.token,
                    volume: selection.volume
                ),
            ],
            notes: selection.token
        )
        return MusicControlPlaybackRequest(
            pattern: pattern,
            loop: false,
            triggerIdentifier: "step:\(part.id.uuidString):\(cell.row):\(cell.column):\(selection.token)"
        )
    }

    private static func stepNoteSelection(
        for part: Part,
        document: HypeDocument,
        cell: (row: Int, column: Int)
    ) -> StepNoteSelection {
        let defaultInstrument = MusicInstrumentCatalog.resolve(part.musicInstrumentName).name
        if let trackSelection = stepNoteFromTracks(for: part, document: document, cell: cell, defaultInstrument: defaultInstrument) {
            return trackSelection
        }

        let rowNotes = defaultStepNotesByRow[min(cell.row, defaultStepNotesByRow.count - 1)]
        let note = rowNotes[cell.column % rowNotes.count]
        return StepNoteSelection(
            token: "\(note)s",
            instrument: defaultInstrument,
            tempo: max(1, Int(part.musicTempo.rounded())),
            volume: part.musicVolume
        )
    }

    private static func stepNoteFromTracks(
        for part: Part,
        document: HypeDocument,
        cell: (row: Int, column: Int),
        defaultInstrument: String
    ) -> StepNoteSelection? {
        let storedTracks = tracks(fromStoredTrackData: part.musicTrackData, defaultInstrument: defaultInstrument)
        if cell.row < storedTracks.count {
            let track = storedTracks[cell.row]
            if let token = noteToken(at: cell.column, in: track.noteString) {
                return StepNoteSelection(
                    token: token,
                    instrument: MusicInstrumentCatalog.resolve(track.instrument).name,
                    tempo: max(1, Int(part.musicTempo.rounded())),
                    volume: track.volume
                )
            }
        }

        guard let pattern = document.musicLibrary.pattern(named: part.musicPatternName) else {
            return nil
        }
        let patternTracks = pattern.tracks.isEmpty
            ? [MusicTrackSpec(name: "melody", instrument: defaultInstrument, noteString: pattern.notes)]
            : pattern.tracks
        guard cell.row < patternTracks.count else { return nil }

        let track = patternTracks[cell.row]
        let notes = track.noteString.isEmpty ? pattern.notes : track.noteString
        guard let token = noteToken(at: cell.column, in: notes) else { return nil }
        return StepNoteSelection(
            token: token,
            instrument: MusicInstrumentCatalog.resolve(track.instrument).name,
            tempo: max(1, pattern.tempo),
            volume: track.volume
        )
    }

    private static func noteToken(at index: Int, in noteString: String) -> String? {
        let tokens = noteString
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !NoteParser.parse($0).isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens[index % tokens.count]
    }

    private static func tracks(fromStoredTrackData trackData: String, defaultInstrument: String) -> [MusicTrackSpec] {
        guard let data = trackData.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.enumerated().map { index, item in
            let rawInstrument = (item["instrument"] as? String) ?? defaultInstrument
            let notes = (item["notes"] as? String)
                ?? (item["noteString"] as? String)
                ?? (item["note_string"] as? String)
                ?? ""
            let volume = (item["volume"] as? Double)
                ?? (item["volume"] as? NSNumber)?.doubleValue
                ?? 1
            let muted = (item["muted"] as? Bool) ?? false
            return MusicTrackSpec(
                name: (item["name"] as? String) ?? "track \(index + 1)",
                instrument: MusicInstrumentCatalog.resolve(rawInstrument).name,
                noteString: muted ? "" : notes,
                volume: volume
            )
        }
    }

    private static func demoPatternRequest(for part: Part) -> MusicControlPlaybackRequest {
        let instrument = MusicInstrumentCatalog.resolve(part.musicInstrumentName).name
        let notes = part.partType == .stepSequencer
            ? "c4s e4s g4s c5s r4s g4s e4s c4s"
            : "c4e e4e g4e c5q"
        return MusicControlPlaybackRequest(
            pattern: MusicPatternSpec(
                name: "\(part.name) Demo",
                tempo: max(1, Int(part.musicTempo.rounded())),
                tracks: [
                    MusicTrackSpec(
                        name: "demo",
                        instrument: instrument,
                        noteString: notes,
                        volume: part.musicVolume
                    ),
                ],
                notes: notes
            ),
            loop: false
        )
    }
}
#endif

public enum MusicPatternRenderer {
    public static func wavData(for pattern: MusicPatternSpec, sampleRate: Int = 44_100) -> Data {
        let notesByTrack = pattern.tracks.filter { !$0.muted }.map { track in
            (track, NoteParser.parse(track.noteString.isEmpty ? pattern.notes : track.noteString))
        }
        let bpm = Double(max(1, pattern.tempo))
        let secondsPerBeat = 60.0 / bpm
        var totalSeconds = 0.25
        for (_, notes) in notesByTrack {
            let beats = notes.reduce(0.0) { $0 + NoteParser.durationInBeats(for: $1) }
            totalSeconds = max(totalSeconds, beats * secondsPerBeat)
        }

        let sampleCount = max(1, Int(ceil(totalSeconds * Double(sampleRate))))
        var samples = Array(repeating: 0.0, count: sampleCount)
        var activeTrackCount = 0
        for (track, notes) in notesByTrack where !notes.isEmpty {
            activeTrackCount += 1
            var cursor = 0.0
            let waveform = waveform(for: track.instrument)
            for note in notes {
                let duration = NoteParser.durationInBeats(for: note) * secondsPerBeat
                let start = Int(cursor * Double(sampleRate))
                let count = max(1, Int(duration * Double(sampleRate)))
                let frequency = NoteParser.frequency(for: note)
                if frequency > 0 {
                    for i in 0..<count where start + i < samples.count {
                        let t = Double(i) / Double(sampleRate)
                        var sample = sampleValue(waveform: waveform, frequency: frequency, time: t)
                        let progress = Double(i) / Double(max(1, count))
                        let envelope = min(1.0, progress / 0.02) * min(1.0, (1.0 - progress) / 0.08)
                        sample *= max(0, min(1, track.volume)) * max(0, envelope) * 0.35
                        samples[start + i] += sample
                    }
                }
                cursor += duration
            }
        }
        let divisor = max(1.0, sqrt(Double(max(1, activeTrackCount))))
        let pcm = samples.map { Int16(max(-1, min(1, $0 / divisor)) * Double(Int16.max)) }
        return makeWAV(pcm: pcm, sampleRate: sampleRate)
    }

    private enum Waveform { case sine, sawtooth, square, triangle }

    private static func waveform(for instrument: String) -> Waveform {
        let descriptor = MusicInstrumentCatalog.resolve(instrument)
        switch descriptor.family {
        case "Piano", "Guitar", "Bass", "Synth Lead", "Percussive":
            return .sawtooth
        case "Chromatic Percussion", "Sound Effects":
            return .square
        case "Strings", "Ensemble", "Synth Pad":
            return .triangle
        default:
            return .sine
        }
    }

    private static func sampleValue(waveform: Waveform, frequency: Double, time: Double) -> Double {
        let phase = frequency * time * 2.0 * .pi
        switch waveform {
        case .sine:
            return sin(phase)
        case .sawtooth:
            return 2.0 * (frequency * time - floor(0.5 + frequency * time))
        case .square:
            return sin(phase) >= 0 ? 1 : -1
        case .triangle:
            return 2.0 * abs(2.0 * (frequency * time - floor(frequency * time + 0.5))) - 1.0
        }
    }

    private static func makeWAV(pcm: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = UInt32(sampleRate * 2)
        let dataSize = UInt32(pcm.count * 2)
        data.append(contentsOf: "RIFF".utf8)
        appendUInt32(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(1, to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(byteRate, to: &data)
        appendUInt16(2, to: &data)
        appendUInt16(16, to: &data)
        data.append(contentsOf: "data".utf8)
        appendUInt32(dataSize, to: &data)
        for var sample in pcm {
            sample = sample.littleEndian
            withUnsafeBytes(of: sample) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var v = value.littleEndian
        withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
    }
}

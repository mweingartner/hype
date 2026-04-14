import Testing
import Foundation
@testable import HypeCore

@Suite("NoteParser Tests")
struct NoteParserTests {

    // MARK: - Parsing

    @Test func basicNoteNames() {
        let notes = NoteParser.parse("c d e f g a b")
        #expect(notes.count == 7)
        #expect(notes[0].name == .c)
        #expect(notes[1].name == .d)
        #expect(notes[2].name == .e)
        #expect(notes[3].name == .f)
        #expect(notes[4].name == .g)
        #expect(notes[5].name == .a)
        #expect(notes[6].name == .b)
        for note in notes {
            #expect(note.octave == 4)
            #expect(note.duration == .quarter)
        }
    }

    @Test func rest() {
        let notes = NoteParser.parse("r")
        #expect(notes.count == 1)
        #expect(notes[0].name == .r)
    }

    @Test func accidentals() {
        let notes = NoteParser.parse("c# db")
        #expect(notes.count == 2)
        #expect(notes[0].name == .c)
        #expect(notes[0].accidental == .sharp)
        #expect(notes[1].name == .d)
        #expect(notes[1].accidental == .flat)
    }

    @Test func explicitOctaves() {
        let notes = NoteParser.parse("c3 c4 c5")
        #expect(notes.count == 3)
        #expect(notes[0].octave == 3)
        #expect(notes[1].octave == 4)
        #expect(notes[2].octave == 5)
    }

    @Test func allDurations() {
        let notes = NoteParser.parse("cw ch cq ce cs ct cx")
        #expect(notes.count == 7)
        #expect(notes[0].duration == .whole)
        #expect(notes[1].duration == .half)
        #expect(notes[2].duration == .quarter)
        #expect(notes[3].duration == .eighth)
        #expect(notes[4].duration == .sixteenth)
        #expect(notes[5].duration == .thirtySecond)
        #expect(notes[6].duration == .sixtyFourth)
    }

    @Test func dottedNote() {
        let notes = NoteParser.parse("cq.")
        #expect(notes.count == 1)
        #expect(notes[0].dotted == true)
        let beats = NoteParser.durationInBeats(for: notes[0])
        #expect(beats == 1.5)
    }

    @Test func tripletNote() {
        let notes = NoteParser.parse("cq3")
        #expect(notes.count == 1)
        #expect(notes[0].triplet == true)
        let beats = NoteParser.durationInBeats(for: notes[0])
        #expect(abs(beats - 2.0 / 3.0) < 0.001)
    }

    @Test func stickyOctave() {
        let notes = NoteParser.parse("c4 e g")
        #expect(notes.count == 3)
        #expect(notes[0].octave == 4)
        #expect(notes[1].octave == 4)
        #expect(notes[2].octave == 4)
    }

    @Test func stickyDuration() {
        let notes = NoteParser.parse("c4q e g")
        #expect(notes.count == 3)
        #expect(notes[0].duration == .quarter)
        #expect(notes[1].duration == .quarter)
        #expect(notes[2].duration == .quarter)
    }

    @Test func complexNotes() {
        let notes = NoteParser.parse("c4q e4q g4q c5h.")
        #expect(notes.count == 4)

        #expect(notes[0].name == .c)
        #expect(notes[0].octave == 4)
        #expect(notes[0].duration == .quarter)

        #expect(notes[1].name == .e)
        #expect(notes[1].octave == 4)
        #expect(notes[1].duration == .quarter)

        #expect(notes[2].name == .g)
        #expect(notes[2].octave == 4)
        #expect(notes[2].duration == .quarter)

        #expect(notes[3].name == .c)
        #expect(notes[3].octave == 5)
        #expect(notes[3].duration == .half)
        #expect(notes[3].dotted == true)
    }

    @Test func emptyString() {
        let notes = NoteParser.parse("")
        #expect(notes.isEmpty)
    }

    // MARK: - Frequency

    @Test func frequencyA4() {
        let note = Note(name: .a, octave: 4)
        let freq = NoteParser.frequency(for: note)
        #expect(abs(freq - 440.0) < 0.01)
    }

    @Test func frequencyC4() {
        let note = Note(name: .c, octave: 4)
        let freq = NoteParser.frequency(for: note)
        #expect(abs(freq - 261.63) < 0.1)
    }

    @Test func frequencyASharp4() {
        let note = Note(name: .a, accidental: .sharp, octave: 4)
        let freq = NoteParser.frequency(for: note)
        #expect(abs(freq - 466.16) < 0.1)
    }

    @Test func frequencyRest() {
        let note = Note(name: .r)
        let freq = NoteParser.frequency(for: note)
        #expect(freq == 0)
    }

    // MARK: - Duration in beats

    @Test func durationBeatsWhole() {
        let note = Note(name: .c, duration: .whole)
        #expect(NoteParser.durationInBeats(for: note) == 4.0)
    }

    @Test func durationBeatsEighth() {
        let note = Note(name: .c, duration: .eighth)
        #expect(NoteParser.durationInBeats(for: note) == 0.5)
    }

    @Test func durationBeatsDottedQuarter() {
        let note = Note(name: .c, duration: .quarter, dotted: true)
        #expect(NoteParser.durationInBeats(for: note) == 1.5)
    }
}

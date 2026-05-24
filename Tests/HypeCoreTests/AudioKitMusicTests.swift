import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import HypeCore

@Suite("AudioKit Music — model, tools, HypeTalk, persistence")
struct AudioKitMusicTests {
    private enum MusicEvent: Equatable, Sendable {
        case play(name: String, loop: Bool)
        case stop
        case pause
        case resume
        case state
    }

    private actor RecordingMusicProvider: SystemProvider {
        private var events: [MusicEvent] = []

        func playMusicPattern(_ pattern: MusicPatternSpec, loop: Bool, document: HypeDocument) async {
            events.append(.play(name: pattern.name, loop: loop))
        }

        func stopMusic() async {
            events.append(.stop)
        }

        func pauseMusic() async {
            events.append(.pause)
        }

        func resumeMusic() async {
            events.append(.resume)
        }

        func currentMusicState() async -> String {
            events.append(.state)
            return "playing"
        }

        func recordedEvents() -> [MusicEvent] {
            events
        }
    }

    private func parses(_ source: String) -> Bool {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return (try? parser.parse()) != nil
    }

    @Test("General MIDI catalog resolves all core instruments and aliases")
    func instrumentCatalog() {
        #expect(MusicInstrumentCatalog.instruments.count >= 129)
        #expect(Set(MusicInstrumentCatalog.instruments.map(\.name)).count == MusicInstrumentCatalog.instruments.count)
        #expect(MusicInstrumentCatalog.resolve("harpsichord").name == "Harpsichord")
        #expect(MusicInstrumentCatalog.resolve("piano").name == "Acoustic Grand Piano")
        #expect(MusicInstrumentCatalog.resolve("drums").isPercussion == true)
        #expect(MusicInstrumentCatalog.displayList.contains("Flute"))
    }

    @Test("Pattern renderer emits a portable WAV asset")
    func rendererProducesWAV() {
        let pattern = MusicPatternSpec.singleTrack(
            name: "Theme",
            instrument: "Harpsichord",
            tempo: 120,
            notes: "c4q e4q g4q c5h"
        )
        let data = MusicPatternRenderer.wavData(for: pattern)
        #expect(data.count > 44)
        #expect(String(data: data.prefix(4), encoding: .ascii) == "RIFF")
        #expect(String(data: data.dropFirst(8).prefix(4), encoding: .ascii) == "WAVE")
    }

    @Test("HypeTalk parser accepts music commands and properties")
    func parserAcceptsMusicCommands() {
        #expect(parses("""
        on mouseUp
          create music pattern "Theme" with instrument "Harpsichord" tempo 120 notes "c4q e4q g4q c5h"
          play pattern "Theme"
          loop pattern "Theme"
          pause music
          resume music
          stop music
          export pattern "Theme" to audio asset "Theme WAV"
          set the instrument of pianoKeyboard "Keys" to "Electric Guitar Clean"
          set the musicPattern of keyboard "Keys" to "Theme"
          set the tempo of musicPlayer "Theme Player" to 120
          set the volume of musicMixer "Mix" to 0.75
          answer the musicState
          answer the musicPatterns
          answer the musicInstruments
        end mouseUp
        """))
    }

    @Test("Interpreter sets music-control properties by HypeTalk object reference")
    func interpreterSetsMusicControlProperties() async throws {
        var document = HypeDocument.newDocument(name: "Music Controls")
        let cardId = document.cards[0].id
        document.musicLibrary.upsertPattern(.singleTrack(
            name: "Sweet Child Guitar",
            instrument: "Electric Guitar Clean",
            tempo: 120,
            notes: "d5e d4e a4e g4e"
        ))
        document.addPart(Part(
            partType: .pianoKeyboard,
            cardId: cardId,
            name: "Keys",
            left: 10,
            top: 20,
            width: 320,
            height: 140
        ))
        document.cards[0].script = """
        on openCard
          set the instrument of pianoKeyboard "Keys" to "Electric Guitar Clean"
          set the musicPattern of keyboard "Keys" to "Sweet Child Guitar"
          set the tempo of keyboard "Keys" to 120
          set the volume of keyboard "Keys" to 0.8
        end openCard
        """

        let runtime = StackRuntime(
            document: document,
            configuration: StackRuntimeConfiguration()
        )
        let result = await runtime.dispatchAndWait(
            "openCard",
            params: [],
            targetId: cardId,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        let keyboard = modified.parts.first { $0.name == "Keys" }
        #expect(keyboard?.musicInstrumentName == "Electric Guitar Clean")
        #expect(keyboard?.musicPatternName == "Sweet Child Guitar")
        #expect(keyboard?.musicTempo == 120)
        #expect(keyboard?.musicVolume == 0.8)
    }

    @Test("Interpreter creates, plays, exports, and reports music state")
    func interpreterMusicLifecycle() async {
        var document = HypeDocument.newDocument(name: "Music Stack")
        let cardId = document.cards[0].id
        var field = Part(partType: .field, cardId: cardId, name: "status")
        document.addPart(field)
        document.cards[0].script = """
        on openCard
          create music pattern "Theme" with instrument "Harpsichord" tempo 120 notes "c4q e4q g4q c5h"
          play pattern "Theme" loop
          pause music
          resume music
          export pattern "Theme" to audio asset "Theme WAV"
          put the musicState into field "status"
          stop music
        end openCard
        """

        let provider = RecordingMusicProvider()
        let runtime = StackRuntime(
            document: document,
            configuration: StackRuntimeConfiguration(systemProvider: provider)
        )
        let result = await runtime.dispatchAndWait(
            "openCard",
            params: [],
            targetId: cardId,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        let modified = try? #require(result.modifiedDocument)
        #expect(modified?.musicLibrary.pattern(named: "Theme") != nil)
        #expect(modified?.spriteRepository.asset(byName: "Theme WAV")?.kind == .audioClip)
        #expect(modified?.parts.first(where: { $0.name == "status" })?.textContent == "playing")
        let events = await provider.recordedEvents()
        #expect(events == [
            .play(name: "Theme", loop: true),
            .pause,
            .resume,
            .state,
            .stop,
        ])
    }

    @Test("SQLite package persists stack-contained music patterns")
    func sqliteMusicRoundTrip() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Music-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        var document = HypeDocument.newDocument(name: "Music Stack")
        document.musicLibrary.upsertPattern(.singleTrack(
            name: "Theme",
            instrument: "Flute",
            tempo: 140,
            notes: "c4q d4q e4q"
        ))

        try store.save(document, toPackageAt: packageURL)
        let loaded = try store.load(fromPackageAt: packageURL)
        let pattern = try #require(loaded.musicLibrary.pattern(named: "Theme"))
        #expect(pattern.tempo == 140)
        #expect(pattern.tracks.first?.instrument == "Flute")
        #expect(pattern.tracks.first?.noteString == "c4q d4q e4q")
    }

    @Test("AI tools create patterns, controls, and portable audio assets")
    func aiTools() async throws {
        var document = HypeDocument.newDocument(name: "Music Tools")
        let cardId = document.cards[0].id
        let executor = HypeToolExecutor()

        _ = await executor.execute(
            toolName: "create_music_pattern",
            arguments: [
                "name": "Theme",
                "instrument": "Harpsichord",
                "tempo": "120",
                "notes": "c4q e4q g4q c5h",
                "loop": "true",
            ],
            document: &document,
            currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "create_music_player",
            arguments: [
                "name": "Theme Player",
                "left": "10", "top": "20", "width": "280", "height": "90",
                "pattern": "Theme",
                "instrument": "Harpsichord",
                "loop": "true",
            ],
            document: &document,
            currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "export_music_pattern",
            arguments: ["name": "Theme", "asset_name": "Theme WAV"],
            document: &document,
            currentCardId: cardId
        )

        let pattern = try #require(document.musicLibrary.pattern(named: "Theme"))
        #expect(pattern.tracks.first?.instrument == "Harpsichord")
        let player = try #require(document.parts.first { $0.partType == .musicPlayer })
        #expect(player.musicPatternName == "Theme")
        #expect(player.musicLoop == true)
        #expect(document.spriteRepository.asset(byName: "Theme WAV")?.mimeType == "audio/wav")
    }

    @Test("Tool catalog exposes music tools to the card authoring surface")
    func toolCatalogIncludesMusic() {
        let names = Set(HypeToolDefinitions.cardControlAuthoringTools.map(\.function.name))
        #expect(names.contains("list_music_instruments"))
        #expect(names.contains("create_music_pattern"))
        #expect(names.contains("list_music_patterns"))
        #expect(names.contains("export_music_pattern"))
        #expect(names.contains("create_music_player"))
        #expect(names.contains("create_piano_keyboard"))
        #expect(names.contains("create_step_sequencer"))
        #expect(names.contains("create_music_mixer"))
    }

    #if canImport(CoreGraphics)
    @Test("Piano Keyboard clicks map to playable one-note patterns")
    func pianoKeyboardClickMapsToNote() throws {
        let document = HypeDocument.newDocument(name: "Keyboard")
        var keyboard = Part(
            partType: .pianoKeyboard,
            cardId: document.cards[0].id,
            name: "Keys",
            left: 10,
            top: 20,
            width: 280,
            height: 140
        )
        keyboard.musicInstrumentName = "Harpsichord"
        keyboard.musicTempo = 160
        keyboard.musicVolume = 0.4

        let whiteRequest = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: 25, y: 70)
        ))
        #expect(whiteRequest.pattern.tracks.first?.noteString == "c4e")
        #expect(whiteRequest.pattern.tracks.first?.instrument == "Harpsichord")
        #expect(whiteRequest.pattern.tracks.first?.volume == 0.4)
        #expect(whiteRequest.pattern.tempo == 160)

        let blackRequest = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: 37, y: 70)
        ))
        #expect(blackRequest.pattern.tracks.first?.noteString == "c#4e")
        #expect(whiteRequest.triggerIdentifier != blackRequest.triggerIdentifier)
        #expect(whiteRequest.triggerIdentifier?.contains("keyboard:") == true)
    }

    @Test("Piano Keyboard drag targets identify key changes")
    func pianoKeyboardDragTargetsIdentifyKeyChanges() throws {
        let document = HypeDocument.newDocument(name: "Keyboard Drag")
        var keyboard = Part(
            partType: .pianoKeyboard,
            cardId: document.cards[0].id,
            name: "Keys",
            left: 10,
            top: 20,
            width: 280,
            height: 140
        )
        keyboard.musicInstrumentName = "Electric Guitar Clean"

        let first = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: 25, y: 70)
        ))
        let repeated = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: 28, y: 70)
        ))
        let next = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: 48, y: 70)
        ))

        #expect(first.pattern.tracks.first?.noteString == "c4e")
        #expect(repeated.triggerIdentifier == first.triggerIdentifier)
        #expect(next.pattern.tracks.first?.noteString == "d4e")
        #expect(next.triggerIdentifier != first.triggerIdentifier)
    }

    @Test("Step Sequencer grid cells audition individual steps")
    func stepSequencerGridCellsAuditionIndividualSteps() throws {
        let document = HypeDocument.newDocument(name: "Step Sequencer")
        var sequencer = Part(
            partType: .stepSequencer,
            cardId: document.cards[0].id,
            name: "Steps",
            left: 10,
            top: 20,
            width: 320,
            height: 180
        )
        sequencer.musicInstrumentName = "Electric Guitar Clean"
        sequencer.musicTempo = 96
        sequencer.musicVolume = 0.5

        let rect = CGRect(x: sequencer.left, y: sequencer.top, width: sequencer.width, height: sequencer.height)
        let grid = MusicControlInteraction.stepSequencerGridRect(in: rect)
        let cellWidth = grid.width / CGFloat(MusicControlInteraction.stepSequencerColumnCount)
        let cellHeight = grid.height / CGFloat(MusicControlInteraction.stepSequencerRowCount)
        func point(row: Int, column: Int) -> CGPoint {
            CGPoint(
                x: grid.minX + CGFloat(column) * cellWidth + cellWidth / 2,
                y: grid.minY + CGFloat(row) * cellHeight + cellHeight / 2
            )
        }

        let topLeft = try #require(MusicControlInteraction.playbackRequest(
            for: sequencer,
            document: document,
            clickPoint: point(row: 0, column: 0)
        ))
        let secondRow = try #require(MusicControlInteraction.playbackRequest(
            for: sequencer,
            document: document,
            clickPoint: point(row: 1, column: 0)
        ))
        let topLaterStep = try #require(MusicControlInteraction.playbackRequest(
            for: sequencer,
            document: document,
            clickPoint: point(row: 0, column: 3)
        ))

        #expect(topLeft.pattern.tracks.first?.noteString == "c5s")
        #expect(secondRow.pattern.tracks.first?.noteString == "g4s")
        #expect(topLaterStep.pattern.tracks.first?.noteString == "g5s")
        #expect(topLeft.pattern.tracks.first?.instrument == "Electric Guitar Clean")
        #expect(topLeft.pattern.tempo == 96)
        #expect(topLeft.pattern.tracks.first?.volume == 0.5)
        #expect(topLeft.triggerIdentifier != secondRow.triggerIdentifier)
        #expect(topLeft.triggerIdentifier != topLaterStep.triggerIdentifier)
    }

    @Test("Step Sequencer uses stored track rows when available")
    func stepSequencerUsesStoredTrackRows() throws {
        let document = HypeDocument.newDocument(name: "Step Tracks")
        var sequencer = Part(
            partType: .stepSequencer,
            cardId: document.cards[0].id,
            name: "Steps",
            left: 10,
            top: 20,
            width: 320,
            height: 180
        )
        sequencer.musicTrackData = """
        [
          {"name":"lead","instrument":"Flute","notes":"c5s d5s e5s","volume":0.4},
          {"name":"bass","instrument":"Electric Bass Finger","notes":"c3s d3s e3s","volume":0.7}
        ]
        """

        let rect = CGRect(x: sequencer.left, y: sequencer.top, width: sequencer.width, height: sequencer.height)
        let grid = MusicControlInteraction.stepSequencerGridRect(in: rect)
        let cellWidth = grid.width / CGFloat(MusicControlInteraction.stepSequencerColumnCount)
        let cellHeight = grid.height / CGFloat(MusicControlInteraction.stepSequencerRowCount)
        let request = try #require(MusicControlInteraction.playbackRequest(
            for: sequencer,
            document: document,
            clickPoint: CGPoint(
                x: grid.minX + cellWidth * 2.5,
                y: grid.minY + cellHeight * 1.5
            )
        ))

        #expect(request.pattern.tracks.first?.noteString == "e3s")
        #expect(request.pattern.tracks.first?.instrument == "Electric Bass Finger")
        #expect(request.pattern.tracks.first?.volume == 0.7)
        #expect(request.triggerIdentifier?.contains(":1:2:") == true)
    }

    @Test("Music controls play their assigned stack pattern when clicked")
    func musicControlClickUsesAssignedPattern() throws {
        var document = HypeDocument.newDocument(name: "Music Player")
        document.musicLibrary.upsertPattern(.singleTrack(
            name: "Theme",
            instrument: "Flute",
            tempo: 140,
            notes: "g4q a4q b4q",
            loop: false
        ))
        var player = Part(
            partType: .musicPlayer,
            cardId: document.cards[0].id,
            name: "Theme Player",
            left: 0,
            top: 0,
            width: 240,
            height: 100
        )
        player.musicPatternName = "Theme"
        player.musicLoop = true

        let request = try #require(MusicControlInteraction.playbackRequest(
            for: player,
            document: document,
            clickPoint: CGPoint(x: 20, y: 60)
        ))
        #expect(request.pattern.name == "Theme")
        #expect(request.pattern.tracks.first?.instrument == "Flute")
        #expect(request.loop == true)
    }

    @Test("AudioKit piano-key playback uses fresh loaded samplers")
    func audioKitPianoPlaybackUsesFreshLoadedSamplers() throws {
        let source = try String(
            contentsOf: packageRoot()
                .appendingPathComponent("Sources/HypeCore/Audio/AudioKitMusicProvider.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("sampler.resetSampler()"))
        #expect(!source.contains("private var samplers: [String: AppleSampler]"))
        #expect(source.contains("private var activeSamplersByToken: [UUID: [AppleSampler]]"))
        #expect(source.contains("activeSamplersByToken[token, default: []].append(sampler)"))
        #expect(source.contains("cleanupSamplers(for: token)"))
        #expect(source.contains("mixer.removeInput(sampler)"))
        #expect(source.contains("stopAllNotes(on: sampler)"))
        #expect(source.contains("sampler.stop(noteNumber: MIDINoteNumber(note), channel: 0)"))
        #expect(source.contains("stopActivePlayback(stopEngine: false)"))
        #expect(source.contains("stopActivePlayback(stopEngine: true)"))
        #expect(!source.contains("self.engine.stop()"))
        #expect(source.contains("let sampler = AppleSampler()"))
        #expect(source.contains("loadProgram(for: descriptor, into: sampler)"))
    }
    #endif

    private func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

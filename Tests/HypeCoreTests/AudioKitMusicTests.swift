import Foundation
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
          answer the musicState
          answer the musicPatterns
          answer the musicInstruments
        end mouseUp
        """))
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
}

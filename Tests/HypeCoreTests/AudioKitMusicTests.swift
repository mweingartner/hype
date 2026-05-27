import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
#if canImport(AppKit)
import AppKit
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

    private enum AppleMusicEvent: Equatable, Sendable {
        case authorize
        case capabilities
        case search(term: String, scope: String, kinds: [String], limit: Int)
        case play(String)
        case playQueue(String)
        case pause
        case resume
        case seek(Double)
        case stop
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

    private actor RecordingAppleMusicProvider: AppleMusicProviding {
        nonisolated var isAvailable: Bool { true }

        private var events: [AppleMusicEvent] = []
        private let results: [AppleMusicItemRef]

        init(results: [AppleMusicItemRef]) {
            self.results = results
        }

        func authorizationStatus() async -> AppleMusicAuthorizationState {
            .authorized
        }

        func requestAuthorization() async -> AppleMusicAuthorizationState {
            events.append(.authorize)
            return .authorized
        }

        func capabilities() async -> AppleMusicCapabilities {
            events.append(.capabilities)
            return AppleMusicCapabilities(
                authorization: .authorized,
                canPlayCatalogContent: true,
                canBecomeSubscriber: false,
                hasCloudLibraryEnabled: true,
                supportsLibraryMutation: false,
                storefront: "us"
            )
        }

        func search(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
            events.append(.search(
                term: request.term,
                scope: request.scope.rawValue,
                kinds: request.itemKinds.map(\.rawValue),
                limit: request.limit
            ))
            return Array(results.prefix(request.limit))
        }

        func play(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws {
            events.append(.play(item.encodedSource))
        }

        func playQueue(_ queue: AppleMusicQueueSpec, engine: AppleMusicPlaybackEngine) async throws {
            events.append(.playQueue(queue.name))
        }

        func pause(engine: AppleMusicPlaybackEngine) async {
            events.append(.pause)
        }

        func resume(engine: AppleMusicPlaybackEngine) async throws {
            events.append(.resume)
        }

        func stop(engine: AppleMusicPlaybackEngine) async {
            events.append(.stop)
        }

        func skipToNext(engine: AppleMusicPlaybackEngine) async throws {}

        func skipToPrevious(engine: AppleMusicPlaybackEngine) async throws {}

        func currentPlaybackState(engine: AppleMusicPlaybackEngine) async -> String {
            events.append(.state)
            return "playing"
        }

        func seek(to position: TimeInterval, engine: AppleMusicPlaybackEngine) async throws {
            events.append(.seek(position))
        }

        func currentPlaybackPosition(engine: AppleMusicPlaybackEngine) async -> TimeInterval {
            42
        }

        func rawAPIRequest(path: String, method: String, body: Data?) async throws -> Data {
            Data("{}".utf8)
        }

        func createPlaylist(name: String, description: String?, items: [AppleMusicItemRef]) async throws -> AppleMusicItemRef {
            throw AppleMusicProviderError.unsupported("Playlist mutation is unavailable in tests.")
        }

        func add(_ item: AppleMusicItemRef, toPlaylist playlist: AppleMusicItemRef?) async throws {
            throw AppleMusicProviderError.unsupported("Library mutation is unavailable in tests.")
        }

        func recordedEvents() -> [AppleMusicEvent] {
            events
        }
    }

    private actor RecordingAppleMusicSystemProvider: SystemProvider {
        private var events: [AppleMusicEvent] = []
        private let results: [AppleMusicItemRef]

        init(results: [AppleMusicItemRef]) {
            self.results = results
        }

        func authorizeAppleMusic() async -> AppleMusicAuthorizationState {
            events.append(.authorize)
            return .authorized
        }

        func appleMusicAuthorizationStatus() async -> AppleMusicAuthorizationState {
            .authorized
        }

        func appleMusicCapabilities() async -> AppleMusicCapabilities {
            events.append(.capabilities)
            return AppleMusicCapabilities(authorization: .authorized, canPlayCatalogContent: true)
        }

        func searchAppleMusic(_ request: AppleMusicSearchRequest) async throws -> [AppleMusicItemRef] {
            events.append(.search(
                term: request.term,
                scope: request.scope.rawValue,
                kinds: request.itemKinds.map(\.rawValue),
                limit: request.limit
            ))
            return Array(results.prefix(request.limit))
        }

        func playAppleMusic(_ item: AppleMusicItemRef, engine: AppleMusicPlaybackEngine) async throws {
            events.append(.play(item.encodedSource))
        }

        func pauseAppleMusic(engine: AppleMusicPlaybackEngine) async {
            events.append(.pause)
        }

        func resumeAppleMusic(engine: AppleMusicPlaybackEngine) async throws {
            events.append(.resume)
        }

        func stopAppleMusic(engine: AppleMusicPlaybackEngine) async {
            events.append(.stop)
        }

        func currentAppleMusicState(engine: AppleMusicPlaybackEngine) async -> String {
            events.append(.state)
            return "playing"
        }

        func seekAppleMusic(to position: Double, engine: AppleMusicPlaybackEngine) async throws {
            events.append(.seek(position))
        }

        func currentAppleMusicPosition(engine: AppleMusicPlaybackEngine) async -> Double {
            42
        }

        func recordedEvents() -> [AppleMusicEvent] {
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
        #expect(AppleMusicItemKind.parse("singer") == .artist)
        #expect(AppleMusicItemKind.parse("play list") == .playlist)
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
          set the showInstrument of pianoKeyboard "Keys" to true
          set the showPattern of pianoKeyboard "Keys" to true
          set the showTempo of pianoKeyboard "Keys" to true
          set the volume of musicMixer "Mix" to 0.75
          answer the musicState
          answer the musicPatterns
          answer the musicInstruments
          authorize appleMusic
          search appleMusic for "Miles Davis" type songs limit 10
          play appleMusic song "123456789"
          seek appleMusic to 30
          pause appleMusic
          resume appleMusic
          stop appleMusic
          authorize apple music
          search apple music library for "Kind of Blue" kind album limit 5
          play apple music album "album123"
          position apple music at 12
          pause apple music
          resume apple music
          stop apple music
          set the musicSource of musicPlayer "Theme Player" to "appleMusicCatalog:song:123456789"
          answer the appleMusicState
          answer the appleMusicAuthorization
          answer the appleMusicCapabilities
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
          set the showControlType of keyboard "Keys" to true
          set the showInstrument of keyboard "Keys" to true
          set the showTempo of keyboard "Keys" to true
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
        #expect(keyboard?.musicShowControlType == true)
        #expect(keyboard?.musicShowInstrument == true)
        #expect(keyboard?.musicShowTempo == true)
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

    @Test("Apple Music references and queues round-trip through SQLite")
    func appleMusicSQLiteRoundTrip() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppleMusic-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        var document = HypeDocument.newDocument(name: "Apple Music Stack")
        document.stack.appleMusicAllowed = true
        let item = AppleMusicItemRef(
            id: "song123",
            kind: .song,
            source: .appleMusicCatalog,
            titleSnapshot: "So What",
            artistSnapshot: "Miles Davis",
            albumSnapshot: "Kind of Blue",
            artworkURLSnapshot: "https://example.invalid/art.jpg",
            durationSnapshot: 545,
            storefront: "us"
        )
        document.musicLibrary.upsertAppleMusicItem(item)
        document.musicLibrary.upsertAppleMusicQueue(AppleMusicQueueSpec(name: "Jazz Queue", items: [item]))

        var player = Part(partType: .musicPlayer, cardId: document.cards[0].id, name: "Apple Player")
        player.musicSourceKind = item.source.rawValue
        player.musicSourceType = item.kind.rawValue
        player.musicSourceID = item.id
        player.musicSourceTitle = item.titleSnapshot
        player.musicSourceArtist = item.artistSnapshot
        player.musicSourceAlbum = item.albumSnapshot
        player.musicArtworkURL = item.artworkURLSnapshot
        player.musicDuration = item.durationSnapshot ?? 0
        player.musicPosition = 12
        document.addPart(player)

        try store.save(document, toPackageAt: packageURL)
        let loaded = try store.load(fromPackageAt: packageURL)

        #expect(loaded.stack.appleMusicAllowed == true)
        let loadedItem = try #require(loaded.musicLibrary.appleMusicItem(id: "song123", kind: .song))
        #expect(loadedItem.titleSnapshot == "So What")
        #expect(loadedItem.artistSnapshot == "Miles Davis")
        #expect(loaded.musicLibrary.appleMusicQueue(named: "Jazz Queue")?.items.first?.id == "song123")
        let loadedPlayer = try #require(loaded.parts.first { $0.name == "Apple Player" })
        #expect(loadedPlayer.musicSourceKind == MusicSourceKind.appleMusicCatalog.rawValue)
        #expect(loadedPlayer.musicSourceID == "song123")
        #expect(loadedPlayer.musicSourceTitle == "So What")
        #expect(loadedPlayer.musicDuration == 545)
        #expect(loadedPlayer.musicPosition == 12)
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

    @Test("AI Apple Music tools require opt-in, preserve privacy, and bind playback references")
    func aiAppleMusicTools() async throws {
        let resultItem = AppleMusicItemRef(
            id: "song123",
            kind: .song,
            source: .appleMusicCatalog,
            titleSnapshot: "So What",
            artistSnapshot: "Miles Davis",
            albumSnapshot: "Kind of Blue"
        )
        let provider = RecordingAppleMusicProvider(results: [resultItem])
        let executor = HypeToolExecutor(
            webAssetSession: nil,
            webAssetClient: nil,
            webAssetPipeline: nil,
            appleMusicProvider: provider
        )
        var document = HypeDocument.newDocument(name: "Music Tools")
        let cardId = document.cards[0].id

        var response = await executor.execute(
            toolName: "search_apple_music",
            arguments: ["query": "Miles Davis"],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("disabled for this stack"))

        document.stack.appleMusicAllowed = true
        response = await executor.execute(
            toolName: "search_apple_music",
            arguments: [
                "query": "Miles Davis",
                "scope": "library",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("include_private_library_context=true"))
        #expect(await provider.recordedEvents().isEmpty)

        response = await executor.execute(
            toolName: "search_apple_music",
            arguments: [
                "query": "Miles Davis",
                "types": "song",
                "limit": "1",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("appleMusicCatalog:song:song123"))
        #expect(document.musicLibrary.appleMusicItem(id: "song123", kind: .song)?.titleSnapshot == "So What")

        _ = await executor.execute(
            toolName: "create_apple_music_browser",
            arguments: [
                "name": "Miles Search",
                "left": "10", "top": "20", "width": "280", "height": "90",
                "query": "Miles Davis",
                "types": "song",
            ],
            document: &document,
            currentCardId: cardId
        )
        let searchControl = try #require(document.parts.first { $0.partType == .appleMusicBrowser })
        #expect(searchControl.musicSearchTerm == "Miles Davis")
        #expect(searchControl.musicSourceType == "song")

        response = await executor.execute(
            toolName: "set_apple_music_selection",
            arguments: [
                "player_name": "Miles Search",
                "item_id": "song123",
                "item_type": "song",
                "source": "appleMusicCatalog",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("So What"))

        response = await executor.execute(
            toolName: "play_apple_music",
            arguments: [
                "item_id": "song123",
                "item_type": "song",
                "source": "appleMusicCatalog",
            ],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("Playing Apple Music song"))
        response = await executor.execute(
            toolName: "seek_apple_music",
            arguments: ["position": "30"],
            document: &document,
            currentCardId: cardId
        )
        #expect(response.contains("30 seconds"))
        let events = await provider.recordedEvents()
        #expect(events.contains(.search(term: "Miles Davis", scope: "catalog", kinds: ["song"], limit: 1)))
        #expect(events.contains(.play("appleMusicCatalog:song:song123")))
        #expect(events.contains(.seek(30)))
    }

    @Test("Interpreter dispatches Apple Music commands through the system provider")
    func interpreterAppleMusicLifecycle() async throws {
        let item = AppleMusicItemRef(
            id: "song123",
            kind: .song,
            source: .appleMusicCatalog,
            titleSnapshot: "So What",
            artistSnapshot: "Miles Davis"
        )
        var document = HypeDocument.newDocument(name: "Apple Music Script")
        document.stack.appleMusicAllowed = true
        let cardId = document.cards[0].id
        document.addPart(Part(partType: .field, cardId: cardId, name: "status"))
        document.cards[0].script = """
        on openCard
          authorize apple music
          search apple music for "Miles Davis" type song limit 1
          play apple music song "song123"
          seek apple music to 30
          pause apple music
          resume apple music
          put the appleMusicPosition into field "status"
          put the appleMusicState into field "status"
          stop apple music
        end openCard
        """

        let provider = RecordingAppleMusicSystemProvider(results: [item])
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
        let modified = try #require(result.modifiedDocument)
        #expect(modified.musicLibrary.appleMusicItem(id: "song123", kind: .song)?.titleSnapshot == "So What")
        #expect(modified.parts.first(where: { $0.name == "status" })?.textContent == "playing")
        let events = await provider.recordedEvents()
        #expect(events == [
            .authorize,
            .search(term: "Miles Davis", scope: "catalog", kinds: ["song"], limit: 1),
            .play("appleMusicCatalog:song:song123"),
            .seek(30),
            .pause,
            .resume,
            .state,
            .stop,
        ])
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
        #expect(names.contains("get_apple_music_capabilities"))
        #expect(names.contains("authorize_apple_music"))
        #expect(names.contains("search_apple_music"))
        #expect(names.contains("set_apple_music_selection"))
        #expect(!names.contains("set_music_player_source"))
        #expect(names.contains("play_apple_music"))
        #expect(names.contains("seek_apple_music"))
        #expect(names.contains("play_music_player"))
        #expect(names.contains("pause_apple_music"))
        #expect(names.contains("resume_apple_music"))
        #expect(names.contains("stop_apple_music"))
        #expect(names.contains("create_apple_music_browser"))
        #expect(!names.contains("create_music_queue"))
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
        let layout = MusicControlInteraction.keyboardLayout(for: keyboard)
        let firstWhite = try #require(layout.whiteKeys.first)
        let firstBlack = try #require(layout.blackKeys.first)

        let whiteRequest = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: firstWhite.frame.midX, y: firstWhite.frame.midY)
        ))
        #expect(whiteRequest.pattern.tracks.first?.noteString == "c2e")
        #expect(whiteRequest.pattern.tracks.first?.instrument == "Harpsichord")
        #expect(whiteRequest.pattern.tracks.first?.volume == 0.4)
        #expect(whiteRequest.pattern.tempo == 160)
        #expect(whiteRequest.sustainedNote?.note == "c2")
        #expect(whiteRequest.sustainedNote?.midiNote == 36)
        #expect(whiteRequest.sustainedNote?.instrument == "Harpsichord")
        #expect(whiteRequest.sustainedNote?.volume == 0.4)

        let blackRequest = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: firstBlack.frame.midX, y: firstBlack.frame.midY)
        ))
        #expect(blackRequest.pattern.tracks.first?.noteString == "c#2e")
        #expect(blackRequest.sustainedNote?.midiNote == 37)
        #expect(whiteRequest.triggerIdentifier != blackRequest.triggerIdentifier)
        #expect(whiteRequest.triggerIdentifier?.contains("keyboard:") == true)
    }

    @Test("Piano Keyboard key-count options use standard playable ranges")
    func pianoKeyboardKeyCountOptionsUseStandardRanges() throws {
        let document = HypeDocument.newDocument(name: "Keyboard Ranges")
        let expected: [(Int, String, String, Int)] = [
            (49, "c2", "c6", 29),
            (61, "c2", "c7", 36),
            (76, "e1", "g7", 45),
            (88, "a0", "c8", 52),
        ]

        for (keyCount, firstNote, lastNote, whiteCount) in expected {
            var keyboard = Part(
                partType: .pianoKeyboard,
                cardId: document.cards[0].id,
                name: "Keys",
                left: 10,
                top: 20,
                width: 520,
                height: 160
            )
            keyboard.musicKeyCount = keyCount

            let layout = MusicControlInteraction.keyboardLayout(for: keyboard)
            #expect(layout.whiteKeys.first?.note == firstNote)
            #expect(layout.whiteKeys.last?.note == lastNote)
            #expect(layout.whiteKeys.count == whiteCount)

            let firstKey = try #require(layout.whiteKeys.first)
            let request = try #require(MusicControlInteraction.playbackRequest(
                for: keyboard,
                document: document,
                clickPoint: CGPoint(x: firstKey.frame.midX, y: firstKey.frame.midY)
            ))
            #expect(request.pattern.tracks.first?.noteString == "\(firstNote)e")
            #expect(request.sustainedNote?.note == firstNote)
            #expect(request.sustainedNote?.midiNote == MusicKeyboardKeyCount.midiRange(for: keyCount).lowerBound)
        }

        #expect(MusicKeyboardKeyCount.normalize(44) == 49)
        #expect(MusicKeyboardKeyCount.normalize(90) == 88)
    }

    @Test("default piano keyboard size has a visible playable key area")
    func defaultPianoKeyboardSizeIsPlayable() throws {
        let document = HypeDocument.newDocument(name: "Default Keyboard")
        let size = PartCreationDefaults.defaultSize(for: .pianoKeyboard)
        let keyboard = Part(
            partType: .pianoKeyboard,
            cardId: document.cards[0].id,
            name: "Keys",
            left: 10,
            top: 20,
            width: size.width,
            height: size.height
        )
        let keyRect = MusicControlInteraction.keyboardRect(for: keyboard)

        #expect(keyRect.width > 20)
        #expect(keyRect.height > 18)

        let request = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: keyRect.minX + 4, y: keyRect.midY)
        ))
        #expect(request.pattern.tracks.first?.noteString == "c2e")
        #expect(request.triggerIdentifier?.contains("keyboard:") == true)
    }

    @Test("Piano Keyboard display metadata is hidden by default and expands only when requested")
    func pianoKeyboardDisplayMetadataDefaultsHidden() throws {
        let document = HypeDocument.newDocument(name: "Keyboard Metadata")
        var keyboard = Part(
            partType: .pianoKeyboard,
            cardId: document.cards[0].id,
            name: "Keys",
            left: 10,
            top: 20,
            width: 280,
            height: 140
        )

        #expect(keyboard.musicShowControlType == false)
        #expect(keyboard.musicShowPattern == false)
        #expect(keyboard.musicShowInstrument == false)
        #expect(keyboard.musicShowTempo == false)
        let hiddenMetadataKeyRect = MusicControlInteraction.keyboardRect(for: keyboard)

        keyboard.musicShowInstrument = true
        keyboard.musicShowPattern = true
        let visibleMetadataKeyRect = MusicControlInteraction.keyboardRect(for: keyboard)
        let popupRect = MusicControlInteraction.pianoKeyboardInstrumentPopupRect(for: keyboard)

        #expect(visibleMetadataKeyRect.minY > hiddenMetadataKeyRect.minY)
        #expect(visibleMetadataKeyRect.height < hiddenMetadataKeyRect.height)
        #expect(popupRect.width > 20)
        #expect(popupRect.height == 24)
    }

    @Test("Step Sequencer display metadata is hidden by default and expands only when requested")
    func stepSequencerDisplayMetadataDefaultsHidden() throws {
        let document = HypeDocument.newDocument(name: "Sequencer Metadata")
        var sequencer = Part(
            partType: .stepSequencer,
            cardId: document.cards[0].id,
            name: "Steps",
            left: 10,
            top: 20,
            width: 320,
            height: 180
        )

        #expect(sequencer.musicShowControlType == false)
        #expect(sequencer.musicShowPattern == false)
        #expect(sequencer.musicShowInstrument == false)
        #expect(sequencer.musicShowTempo == false)
        let hiddenMetadataGrid = MusicControlInteraction.stepSequencerGridRect(for: sequencer)

        sequencer.musicShowInstrument = true
        sequencer.musicShowTempo = true
        let visibleMetadataGrid = MusicControlInteraction.stepSequencerGridRect(for: sequencer)
        let popupRect = MusicControlInteraction.musicInstrumentPopupRect(for: sequencer)

        #expect(visibleMetadataGrid.minY > hiddenMetadataGrid.minY)
        #expect(visibleMetadataGrid.height < hiddenMetadataGrid.height)
        #expect(popupRect.width > 20)
        #expect(popupRect.height == 24)
    }

    @Test("Music tempos clamp to integer BPM range")
    func musicTemposClampToIntegerRange() async throws {
        #expect(MusicTempo.minimum == 1)
        #expect(MusicTempo.maximum == 320)
        #expect(MusicTempo.defaultBPM == 120)
        #expect(MusicTempo.clamp(0) == 1)
        #expect(MusicTempo.clamp(999) == 320)
        #expect(MusicTempo.clamp(120.6) == 121)
        #expect(MusicPatternSpec.singleTrack(name: "Too Fast", instrument: "Flute", tempo: 999, notes: "c4q").tempo == 320)

        var document = HypeDocument.newDocument(name: "Tempo Clamp")
        let cardId = document.cards[0].id
        document.addPart(Part(
            partType: .pianoKeyboard,
            cardId: cardId,
            name: "Keys",
            left: 10,
            top: 20,
            width: 280,
            height: 140
        ))
        document.cards[0].script = """
        on openCard
          create music pattern "Too Slow" with instrument "Flute" tempo 0 notes "c4q"
          set the tempo of pianoKeyboard "Keys" to 999
        end openCard
        """

        let runtime = StackRuntime(document: document, configuration: StackRuntimeConfiguration())
        let result = await runtime.dispatchAndWait("openCard", params: [], targetId: cardId, currentCardId: cardId)

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        #expect(modified.musicLibrary.pattern(named: "Too Slow")?.tempo == 1)
        #expect(modified.parts.first(where: { $0.name == "Keys" })?.musicTempo == 320)

        var toolDocument = HypeDocument.newDocument(name: "Tempo Tool Clamp")
        let toolCardId = toolDocument.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_step_sequencer",
            arguments: [
                "name": "Steps",
                "left": "10", "top": "20", "width": "320", "height": "180",
                "tempo": "999.7",
            ],
            document: &toolDocument,
            currentCardId: toolCardId
        )
        let sequencer = try #require(toolDocument.parts.first { $0.partType == .stepSequencer })
        #expect(sequencer.musicTempo == 320)
    }

    @Test("Piano Keyboard key count is gettable and settable through HypeTalk and tools")
    func pianoKeyboardKeyCountIsScriptableAndToolSettable() async throws {
        var document = HypeDocument.newDocument(name: "Keyboard Keys")
        let cardId = document.cards[0].id
        document.addPart(Part(
            partType: .pianoKeyboard,
            cardId: cardId,
            name: "Keys",
            left: 10,
            top: 20,
            width: 420,
            height: 150
        ))
        document.cards[0].script = """
        on openCard
          set the keyCount of pianoKeyboard "Keys" to 88
          put the keys of pianoKeyboard "Keys" into field "status"
        end openCard
        """
        document.addPart(Part(
            partType: .field,
            cardId: cardId,
            name: "status",
            left: 10,
            top: 180,
            width: 120,
            height: 24
        ))

        let runtime = StackRuntime(document: document, configuration: StackRuntimeConfiguration())
        let result = await runtime.dispatchAndWait("openCard", params: [], targetId: cardId, currentCardId: cardId)

        #expect(result.status == .completed)
        let modified = try #require(result.modifiedDocument)
        #expect(modified.parts.first(where: { $0.name == "Keys" })?.musicKeyCount == 88)
        #expect(modified.parts.first(where: { $0.name == "status" })?.textContent == "88")

        var toolDocument = HypeDocument.newDocument(name: "Keyboard Tool Keys")
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_piano_keyboard",
            arguments: [
                "name": "Tool Keys",
                "left": "10", "top": "20", "width": "420", "height": "150",
                "keys": "76",
            ],
            document: &toolDocument,
            currentCardId: toolDocument.cards[0].id
        )
        #expect(toolDocument.parts.first(where: { $0.name == "Tool Keys" })?.musicKeyCount == 76)
    }

    #if canImport(AppKit)
    @MainActor
    @Test("Live instrument popup overlay suppresses duplicate CG popup chrome")
    func liveInstrumentPopupOverlaySuppressesDuplicateCGPopupChrome() throws {
        var popupPart = Part(
            partType: .pianoKeyboard,
            cardId: UUID(),
            name: "Keys",
            left: 0,
            top: 0,
            width: 300,
            height: 140
        )
        popupPart.musicShowInstrument = true
        popupPart.musicShowTempo = true
        popupPart.musicInstrumentName = "Electric Guitar Clean"

        var noInstrumentPart = popupPart
        noInstrumentPart.musicShowInstrument = false

        let defaultRender = renderMusicControlBytes(part: popupPart)
        let livePopupRender = renderMusicControlBytes(
            part: popupPart,
            options: MusicControlRenderOptions(liveInstrumentPopupPartIds: [popupPart.id])
        )
        let noInstrumentRender = renderMusicControlBytes(part: noInstrumentPart)

        #expect(defaultRender != livePopupRender)
        #expect(livePopupRender == noInstrumentRender)
    }

    @MainActor
    @Test("Piano Keyboard rendering changes when a key is pressed")
    func pianoKeyboardRenderingHighlightsPressedKey() throws {
        let part = Part(
            partType: .pianoKeyboard,
            cardId: UUID(),
            name: "Keys",
            left: 0,
            top: 0,
            width: 420,
            height: 150
        )

        let normalRender = renderMusicControlBytes(part: part)
        let pressedRender = renderMusicControlBytes(
            part: part,
            options: MusicControlRenderOptions(activeKeyboardNotesByPartId: [part.id: "c2"])
        )

        #expect(normalRender != pressedRender)
    }
    #endif

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
        let layout = MusicControlInteraction.keyboardLayout(for: keyboard)
        let firstKey = try #require(layout.whiteKeys.first)
        let secondKey = try #require(layout.whiteKeys.dropFirst().first)

        let first = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: firstKey.frame.midX, y: firstKey.frame.midY)
        ))
        let repeated = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: firstKey.frame.midX + 1, y: firstKey.frame.midY)
        ))
        let next = try #require(MusicControlInteraction.playbackRequest(
            for: keyboard,
            document: document,
            clickPoint: CGPoint(x: secondKey.frame.midX, y: secondKey.frame.midY)
        ))

        #expect(first.pattern.tracks.first?.noteString == "c2e")
        #expect(first.sustainedNote?.midiNote == 36)
        #expect(repeated.triggerIdentifier == first.triggerIdentifier)
        #expect(next.pattern.tracks.first?.noteString == "d2e")
        #expect(next.sustainedNote?.midiNote == 38)
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

        let grid = MusicControlInteraction.stepSequencerGridRect(for: sequencer)
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
        let topLeftRepeat = try #require(MusicControlInteraction.playbackRequest(
            for: sequencer,
            document: document,
            clickPoint: CGPoint(
                x: grid.minX + cellWidth * 0.75,
                y: grid.minY + cellHeight * 0.25
            )
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
        #expect(topLeftRepeat.triggerIdentifier == topLeft.triggerIdentifier)
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

        let grid = MusicControlInteraction.stepSequencerGridRect(for: sequencer)
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

    @Test("AudioKit music players ignore Apple Music references during browse playback")
    func audioKitMusicPlayerIgnoresAppleMusicReference() throws {
        var document = HypeDocument.newDocument(name: "Apple Music Player")
        document.stack.appleMusicAllowed = true
        let item = AppleMusicItemRef(
            id: "song123",
            kind: .song,
            source: .appleMusicCatalog,
            titleSnapshot: "So What",
            artistSnapshot: "Miles Davis"
        )
        document.musicLibrary.upsertAppleMusicItem(item)
        var player = Part(
            partType: .musicPlayer,
            cardId: document.cards[0].id,
            name: "Apple Player",
            left: 0,
            top: 0,
            width: 240,
            height: 100
        )
        player.musicSourceKind = item.source.rawValue
        player.musicSourceType = item.kind.rawValue
        player.musicSourceID = item.id
        player.musicSourceTitle = item.titleSnapshot
        player.musicSourceArtist = item.artistSnapshot

        let request = try #require(MusicControlInteraction.playbackRequest(
            for: player,
            document: document,
            clickPoint: CGPoint(x: 20, y: 60)
        ))
        #expect(request.appleMusicItem == nil)
        #expect(request.pattern.name == "Apple Player Demo")
        #expect(request.loop == false)
    }

    @Test("MusicKit Search controls do not masquerade as AudioKit playback controls")
    func musicKitSearchControlDoesNotCreateAudioKitPlaybackRequest() throws {
        var document = HypeDocument.newDocument(name: "MusicKit Search")
        var search = Part(
            partType: .appleMusicBrowser,
            cardId: document.cards[0].id,
            name: "Miles Search",
            left: 0,
            top: 0,
            width: 320,
            height: 120
        )
        search.musicSearchTerm = "Miles Davis"
        search.musicSourceType = AppleMusicItemKind.song.rawValue
        search.musicSearchScope = AppleMusicSearchScope.catalog.rawValue
        document.addPart(search)

        #expect(MusicControlInteraction.playbackRequest(
            for: search,
            document: document,
            clickPoint: CGPoint(x: 20, y: 60)
        ) == nil)
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
        #expect(source.contains("private var sustainedSamplersByID: [UUID: SustainedSampler]"))
        #expect(source.contains("public func playSustainedNote(_ note: MusicSustainedNoteSpec)"))
        #expect(source.contains("sampler.play("))
        #expect(source.contains("public func stopSustainedNote(id: UUID)"))
        #expect(source.contains("public func stopSustainedNotes(forPart partId: UUID?)"))
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

#if canImport(AppKit)
@MainActor
private func renderMusicControlBytes(
    part: Part,
    options: MusicControlRenderOptions = .default
) -> [UInt8] {
    let size = NSSize(width: part.width, height: part.height)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let gfx = NSGraphicsContext(bitmapImageRep: rep) else {
        return []
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = gfx
    let ctx = gfx.cgContext
    ctx.translateBy(x: 0, y: size.height)
    ctx.scaleBy(x: 1, y: -1)

    let draw = {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        MusicControlsRenderer.draw(
            part.partType,
            ctx: ctx,
            part: part,
            rect: CGRect(origin: .zero, size: size),
            options: options
        )
    }
    if let aqua = NSAppearance(named: .aqua) {
        aqua.performAsCurrentDrawingAppearance(draw)
    } else {
        draw()
    }

    guard let data = rep.bitmapData else { return [] }
    return Array(UnsafeBufferPointer(start: data, count: rep.bytesPerRow * rep.pixelsHigh))
}
#endif

import Testing
import Foundation
import SQLite3
@testable import HypeCore

/// AVFoundation-backed audio recorder part. Tests focus on the
/// model + AI tool + parser surface; live AVAudioRecorder is not
/// instantiated (would require a microphone in CI).
@Suite("Audio Recorder — model, AI tools, HypeTalk grammar")
struct AudioRecorderTests {

    // MARK: - Model

    @Test("Defaults: not recording, not playing, m4a format, empty path")
    func defaults() {
        let part = Part(partType: .audioRecorder, name: "memo")
        #expect(part.partType == .audioRecorder)
        #expect(part.audioRecording == false)
        #expect(part.audioPlaying == false)
        #expect(part.audioFormat == "m4a")
        #expect(part.audioOutputPath == "")
        #expect(part.audioDuration == 0)
        #expect(part.audioEmbedInStack == false)
        #expect(part.audioData == nil)
    }

    @Test("Audio fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .audioRecorder, name: "memo")
        part.audioRecording = true
        part.audioPlaying = true
        part.audioFormat = "caf"
        part.audioOutputPath = "/tmp/memo.caf"
        part.audioDuration = 12.5
        part.audioEmbedInStack = true
        part.audioData = Data([0x01, 0x02, 0x03, 0x04])
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.audioRecording == true)
        #expect(decoded.audioPlaying == true)
        #expect(decoded.audioFormat == "caf")
        #expect(decoded.audioOutputPath == "/tmp/memo.caf")
        #expect(decoded.audioDuration == 12.5)
        #expect(decoded.audioEmbedInStack == true)
        #expect(decoded.audioData == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test("Old documents without newer audio fields decode with defaults")
    func playingBackwardCompat() throws {
        var part = Part(partType: .audioRecorder, name: "memo")
        part.audioOutputPath = "/tmp/memo.m4a"
        let data = try JSONEncoder().encode(part)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "audioPlaying")
        json.removeValue(forKey: "audioEmbedInStack")
        json.removeValue(forKey: "audioData")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.audioPlaying == false)
        #expect(decoded.audioEmbedInStack == false)
        #expect(decoded.audioData == nil)
        #expect(decoded.audioOutputPath == "/tmp/memo.m4a")
    }

    @Test("Embedded audio persists as a SQLite BLOB inside the stack package")
    func embeddedAudioSQLiteBlobRoundTrip() throws {
        let store = HypeSQLiteStackStore()
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EmbeddedAudio-\(UUID().uuidString).hype", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: packageURL) }

        var document = HypeDocument.newDocument(name: "Audio Stack")
        let cardId = try #require(document.cards.first?.id)
        let bytes = Data([0x00, 0x10, 0x20, 0x30, 0x40, 0x50])
        var part = Part(partType: .audioRecorder, cardId: cardId, name: "memo", left: 20, top: 20, width: 180, height: 44)
        part.audioEmbedInStack = true
        part.audioOutputPath = "/tmp/should-not-be-required.m4a"
        part.audioData = bytes
        document.addPart(part)

        try store.save(document, toPackageAt: packageURL)

        let loaded = try store.load(fromPackageAt: packageURL)
        let loadedPart = try #require(loaded.parts.first { $0.name == "memo" })
        #expect(loadedPart.audioEmbedInStack == true)
        #expect(loadedPart.audioData == bytes)

        let stored = try storedAudioBlobAndPayload(packageURL: packageURL, partId: part.id)
        #expect(stored.audioData == bytes)
        #expect(!stored.payloadJSON.contains("audioData"))
    }

    // MARK: - AI tools

    @Test("create_audio_recorder builds a recorder part with format + path")
    func aiCreate() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: [
                "name": "memo",
                "left": "0", "top": "0", "width": "180", "height": "44",
                "format": "caf",
                "output_path": "/tmp/memo.caf"
            ],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .audioRecorder }
        #expect(part?.audioFormat == "caf")
        #expect(part?.audioOutputPath == "/tmp/memo.caf")
        #expect(part?.audioRecording == false)
    }

    @Test("create_audio_recorder can mark recordings for stack storage")
    func aiCreateSaveInStack() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: [
                "name": "memo",
                "left": "0", "top": "0", "width": "180", "height": "44",
                "save_in_stack": "true"
            ],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .audioRecorder }?.audioEmbedInStack == true)
    }

    @Test("Unknown format falls back to m4a")
    func aiCreateUnknownFormat() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: ["name": "memo", "left": "0", "top": "0", "width": "180", "height": "44", "format": "wav"],
            document: &doc, currentCardId: cardId
        )
        let part = doc.parts.first { $0.partType == .audioRecorder }
        #expect(part?.audioFormat == "m4a")
    }

    @Test("set_part_property toggles recording flag")
    func aiSetRecording() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: ["name": "memo", "left": "0", "top": "0", "width": "180", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "memo", "property": "recording", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .audioRecorder }?.audioRecording == true)
    }

    @Test("set_part_property toggles playing flag")
    func aiSetPlaying() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: ["name": "memo", "left": "0", "top": "0", "width": "180", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "memo", "property": "playing", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .audioRecorder }?.audioPlaying == true)
    }

    @Test("set_part_property toggles save-in-stack flag")
    func aiSetSaveInStack() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "create_audio_recorder",
            arguments: ["name": "memo", "left": "0", "top": "0", "width": "180", "height": "44"],
            document: &doc, currentCardId: cardId
        )
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "memo", "property": "saveInStack", "value": "true"],
            document: &doc, currentCardId: cardId
        )
        #expect(doc.parts.first { $0.partType == .audioRecorder }?.audioEmbedInStack == true)
    }

    @Test("get_part_property reads playing flag")
    func aiGetPlaying() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .audioRecorder, cardId: cardId, name: "memo", left: 0, top: 0, width: 180, height: 44)
        part.audioPlaying = true
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "memo", "property": "playing"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "true")
    }

    @Test("get_part_property reads duration as a string")
    func aiGetDuration() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .audioRecorder, cardId: cardId, name: "memo", left: 0, top: 0, width: 180, height: 44)
        part.audioDuration = 7.5
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let result = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "memo", "property": "duration"],
            document: &doc, currentCardId: cardId
        )
        #expect(result == "7.5")
    }

    @Test("get_part_property reads embedded audio state")
    func aiGetEmbeddedAudioState() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        var part = Part(partType: .audioRecorder, cardId: cardId, name: "memo", left: 0, top: 0, width: 180, height: 44)
        part.audioEmbedInStack = true
        part.audioData = Data([0x01, 0x02])
        doc.addPart(part)
        let executor = HypeToolExecutor()
        let saveInStack = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "memo", "property": "saveInStack"],
            document: &doc, currentCardId: cardId
        )
        let audioSize = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "memo", "property": "audioSize"],
            document: &doc, currentCardId: cardId
        )
        #expect(saveInStack == "true")
        #expect(audioSize == "2")
    }

    // MARK: - HypeTalk grammar

    @Test("Parser accepts `the duration of recorder \"X\"`")
    func hypeTalkRecorder() throws {
        let source = "the duration of recorder \"memo\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "duration",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "recorder")
        } else {
            Issue.record("expected propertyAccess(duration, objectRef(recorder, ...)), got \(expr)")
        }
    }

    @Test("Parser accepts `the playing of recorder \"X\"`")
    func hypeTalkPlaying() throws {
        let source = "the playing of recorder \"memo\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "playing",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "recorder")
        } else {
            Issue.record("expected propertyAccess(playing, objectRef(recorder, ...)), got \(expr)")
        }
    }

    @Test("Parser accepts `the saveInStack of recorder \"X\"`")
    func hypeTalkSaveInStack() throws {
        let source = "the saveInStack of recorder \"memo\""
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        let expr = try parser.parseExpression()
        if case .propertyAccess(let prop, let target) = expr,
           prop == "saveInStack",
           case .objectRef(let ref) = target ?? .literal("") {
            #expect(ref.objectType == "recorder")
        } else {
            Issue.record("expected propertyAccess(saveInStack, objectRef(recorder, ...)), got \(expr)")
        }
    }

    private func storedAudioBlobAndPayload(packageURL: URL, partId: UUID) throws -> (audioData: Data?, payloadJSON: String) {
        let sqliteURL = packageURL.appendingPathComponent(HypeSQLiteStackStore.sqliteFileName)
        var db: OpaquePointer?
        guard sqlite3_open_v2(sqliteURL.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK, let db else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT audio_data, payload_json FROM parts WHERE id = ?", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, partId.uuidString, -1, transient)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let audioData: Data?
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            audioData = nil
        } else {
            let count = Int(sqlite3_column_bytes(statement, 0))
            if count == 0 {
                audioData = Data()
            } else if let bytes = sqlite3_column_blob(statement, 0) {
                audioData = Data(bytes: bytes, count: count)
            } else {
                audioData = nil
            }
        }
        let payload = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        return (audioData, payload)
    }
}

import Testing
import Foundation
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
    }

    @Test("Audio fields round-trip through Codable")
    func codable() throws {
        var part = Part(partType: .audioRecorder, name: "memo")
        part.audioRecording = true
        part.audioPlaying = true
        part.audioFormat = "caf"
        part.audioOutputPath = "/tmp/memo.caf"
        part.audioDuration = 12.5
        let data = try JSONEncoder().encode(part)
        let decoded = try JSONDecoder().decode(Part.self, from: data)
        #expect(decoded.audioRecording == true)
        #expect(decoded.audioPlaying == true)
        #expect(decoded.audioFormat == "caf")
        #expect(decoded.audioOutputPath == "/tmp/memo.caf")
        #expect(decoded.audioDuration == 12.5)
    }

    @Test("Old documents without audioPlaying decode with default false")
    func playingBackwardCompat() throws {
        var part = Part(partType: .audioRecorder, name: "memo")
        part.audioOutputPath = "/tmp/memo.m4a"
        let data = try JSONEncoder().encode(part)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "audioPlaying")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.audioPlaying == false)
        #expect(decoded.audioOutputPath == "/tmp/memo.m4a")
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
}

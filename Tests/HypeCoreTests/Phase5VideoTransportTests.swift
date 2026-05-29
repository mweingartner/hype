import Testing
import Foundation
@testable import HypeCore

// MARK: - Helpers

/// Build a minimal document with a video part for interpreter dispatch.
private func makeDoc5V() -> (doc: HypeDocument, cardId: UUID, videoId: UUID) {
    var doc = HypeDocument.newDocument(name: "Phase5VideoTest")
    let cardId = doc.sortedCards[0].id
    let video = Part(partType: .video, cardId: cardId, name: "Vid",
                     left: 0, top: 0, width: 320, height: 240)
    doc.addPart(video)
    return (doc, cardId, video.id)
}

/// Build a minimal document with a button and a video part.
private func makeDoc5VB() -> (doc: HypeDocument, cardId: UUID, btnId: UUID, videoId: UUID) {
    var doc = HypeDocument.newDocument(name: "Phase5VideoBtnTest")
    let cardId = doc.sortedCards[0].id
    let btn = Part(partType: .button, cardId: cardId, name: "Btn",
                   left: 0, top: 0, width: 80, height: 30)
    let video = Part(partType: .video, cardId: cardId, name: "MyVideo",
                     left: 0, top: 50, width: 320, height: 240)
    doc.addPart(btn)
    doc.addPart(video)
    return (doc, cardId, btn.id, video.id)
}

// MARK: - Part model tests

@Suite("Phase 5 — Part video transport fields", .serialized)
struct Phase5PartVideoFieldTests {

    @Test("Part init defaults: videoCurrentTime=0, videoDuration=0, videoPlayRate=1")
    func initDefaults() {
        let cardId = UUID()
        let part = Part(partType: .video, cardId: cardId, name: "v",
                        left: 0, top: 0, width: 100, height: 100)
        #expect(part.videoCurrentTime == 0)
        #expect(part.videoDuration == 0)
        #expect(part.videoPlayRate == 1)
    }

    @Test("Part encodes and decodes video transport fields via JSON round-trip")
    func jsonRoundTrip() throws {
        let cardId = UUID()
        var part = Part(partType: .video, cardId: cardId, name: "v",
                        left: 0, top: 0, width: 100, height: 100)
        part.videoCurrentTime = 12.5
        part.videoDuration = 120.0
        part.videoPlayRate = 1.5

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(part)
        let decoded = try decoder.decode(Part.self, from: data)

        #expect(decoded.videoCurrentTime == 12.5)
        #expect(decoded.videoDuration == 120.0)
        #expect(decoded.videoPlayRate == 1.5)
    }

    @Test("Part JSON missing video fields defaults to 0/0/1 (backward-compat)")
    func jsonMissingFieldsDefaults() throws {
        // Build a minimal JSON for a video Part WITHOUT the three new fields.
        // We do this by encoding a clean Part (which will have defaults) and
        // then stripping out the three keys, mimicking an older document.
        let cardId = UUID()
        let part = Part(partType: .video, cardId: cardId, name: "v",
                        left: 0, top: 0, width: 100, height: 100)
        let encoder = JSONEncoder()
        var dict = try JSONSerialization.jsonObject(
            with: encoder.encode(part)) as! [String: Any]
        dict.removeValue(forKey: "videoCurrentTime")
        dict.removeValue(forKey: "videoDuration")
        dict.removeValue(forKey: "videoPlayRate")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Part.self, from: stripped)
        #expect(decoded.videoCurrentTime == 0, "missing videoCurrentTime should default to 0")
        #expect(decoded.videoDuration == 0, "missing videoDuration should default to 0")
        #expect(decoded.videoPlayRate == 1, "missing videoPlayRate should default to 1")
    }
}

// MARK: - Interpreter property round-trip tests

@Suite("Phase 5 — Interpreter video transport properties", .serialized)
struct Phase5InterpreterVideoPropertyTests {

    // MARK: currentTime

    @Test("set the currentTime of video then get returns same value")
    func currentTimeSetGet() async {
        let (doc, cardId, _, videoId) = makeDoc5VB()
        var d = doc
        d.updatePart(id: videoId) { $0.videoURL = "video.mp4" }
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the currentTime of video "MyVideo" to 12.5
  put the currentTime of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "currentTime set/get should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "12.5", "field should contain '12.5', got '\(txt)'")
    }

    @Test("currentTime setter clamps negative values to 0")
    func currentTimeClampedToZero() async {
        let (doc, cardId, _, _) = makeDoc5VB()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the currentTime of video "MyVideo" to -5
  put the currentTime of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "negative currentTime should not error: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        // max(0, -5) == 0
        #expect(txt == "0", "clamped to 0, got '\(txt)'")
    }

    // MARK: playRate

    @Test("set the playRate of video then get returns same value")
    func playRateSetGet() async {
        let (doc, cardId, _, _) = makeDoc5VB()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the playRate of video "MyVideo" to 2
  put the playRate of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "playRate set/get should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "2", "field should contain '2', got '\(txt)'")
    }

    @Test("playRate setter clamps absurd values to AVPlayer range (review Finding 2)")
    func playRateClamped() async {
        // An out-of-range script value (999 / -999) must be bounded to [-4, 4]
        // so it can't poison the AVPlayer playback engine.
        for (input, expected) in [("999", "4"), ("-999", "-4")] {
            let (doc, cardId, _, _) = makeDoc5VB()
            var d = doc
            let fld = Part(partType: .field, cardId: cardId, name: "Out",
                           left: 0, top: 300, width: 200, height: 30)
            d.addPart(fld)
            let fieldId = fld.id
            let btnId = d.parts.first(where: { $0.partType == .button })!.id
            d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the playRate of video "MyVideo" to \(input)
  put the playRate of video "MyVideo" into field "Out"
end mouseUp
""" }
            let dispatcher = MessageDispatcher()
            let result = await runOnLargeStack { [d] in
                dispatcher.dispatch(
                    message: "mouseUp", params: [], targetId: btnId,
                    document: d, currentCardId: cardId,
                    fileProvider: StubFileAccessProvider()
                )
            }
            #expect(result.status != .error,
                    "clamped playRate should not error: \(result.error?.message ?? "nil")")
            let modified = result.modifiedDocument ?? d
            let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
            #expect(txt == expected, "playRate \(input) should clamp to \(expected), got '\(txt)'")
        }
    }

    @Test("play_rate alias works for playRate property")
    func playRateAliasWorks() async {
        let (doc, cardId, _, _) = makeDoc5VB()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the play_rate of video "MyVideo" to 0.5
  put the rate of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "play_rate alias should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "0.5", "rate alias should return 0.5, got '\(txt)'")
    }

    // MARK: duration (getter only — three-way disambiguation)

    @Test("the duration of video part returns videoDuration")
    func durationOfVideoReturnsVideoDuration() async {
        let (doc, cardId, _, _) = makeDoc5VB()
        var d = doc
        // Directly set videoDuration on the video part (simulating what the canvas
        // host would write after the AVPlayerItem duration becomes known).
        d.updatePart(id: d.parts.first(where: { $0.partType == .video })!.id) {
            $0.videoDuration = 90.0
            // Also set audioDuration to a different value to verify disambiguation.
            $0.audioDuration = 999.0
        }
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  put the duration of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "duration getter should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "90", "video duration should be 90, got '\(txt)'")
    }

    @Test("the duration of audioRecorder part returns audioDuration (not videoDuration)")
    func durationOfAudioReturnsAudioDuration() async {
        var doc = HypeDocument.newDocument(name: "Phase5AudioDurTest")
        let cardId = doc.sortedCards[0].id
        let btn = Part(partType: .button, cardId: cardId, name: "Btn",
                       left: 0, top: 0, width: 80, height: 30)
        let recorder = Part(partType: .audioRecorder, cardId: cardId, name: "Rec",
                            left: 0, top: 50, width: 200, height: 50)
        doc.addPart(btn)
        doc.addPart(recorder)
        var d = doc
        d.updatePart(id: recorder.id) {
            $0.audioDuration = 45.0
            $0.videoDuration = 999.0  // Must NOT be returned
        }
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        d.updatePart(id: btn.id) { $0.script = """
on mouseUp
  put the duration of audioRecorder "Rec" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btn.id,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "audio duration getter should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "45", "audioRecorder duration should be 45, got '\(txt)'")
    }

    // MARK: current_time alias

    @Test("current_time alias works for currentTime property")
    func currentTimeAliasWorks() async {
        let (doc, cardId, _, _) = makeDoc5VB()
        var d = doc
        let fld = Part(partType: .field, cardId: cardId, name: "Out",
                       left: 0, top: 300, width: 200, height: 30)
        d.addPart(fld)
        let fieldId = fld.id
        let btnId = d.parts.first(where: { $0.partType == .button })!.id
        d.updatePart(id: btnId) { $0.script = """
on mouseUp
  set the current_time of video "MyVideo" to 7.75
  put the currentTime of video "MyVideo" into field "Out"
end mouseUp
""" }
        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [d] in
            dispatcher.dispatch(
                message: "mouseUp", params: [], targetId: btnId,
                document: d, currentCardId: cardId,
                fileProvider: StubFileAccessProvider()
            )
        }
        #expect(result.status != .error,
                "current_time alias should succeed: \(result.error?.message ?? "nil")")
        let modified = result.modifiedDocument ?? d
        let txt = modified.parts.first(where: { $0.id == fieldId })?.textContent ?? ""
        #expect(txt == "7.75", "currentTime alias should return 7.75, got '\(txt)'")
    }
}

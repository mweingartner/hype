import Testing
import Foundation
@testable import HypeCore

@Suite("Play/Beep/Wait Command Tests", .serialized)
struct PlayCommandTests {

    private enum RecordedSystemEvent: Equatable, Sendable {
        case beep(Int)
        case playSound(String)
        case playNotes(instrument: String, notes: String, tempo: Int)
        case stop
        case currentSoundName
    }

    private actor RecordingSystemProvider: SystemProvider {
        private var events: [RecordedSystemEvent] = []
        private var soundNames: [String]

        init(soundNames: [String] = Array(repeating: "done", count: 16)) {
            self.soundNames = soundNames
        }

        func beep(count: Int) async {
            events.append(.beep(count))
        }

        func playSound(name: String, document: HypeDocument) async {
            events.append(.playSound(name))
        }

        func playNotes(instrument: String, noteString: String, tempo: Int, document: HypeDocument) async {
            events.append(.playNotes(instrument: instrument, notes: noteString, tempo: tempo))
        }

        func stopSound() async {
            events.append(.stop)
        }

        func currentSoundName() async -> String {
            events.append(.currentSoundName)
            if soundNames.isEmpty { return "done" }
            return soundNames.removeFirst()
        }

        func recordedEvents() -> [RecordedSystemEvent] {
            events
        }
    }

    // MARK: - Helpers

    private func parse(_ source: String) -> Script? {
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        return try? parser.parse()
    }

    private func parses(_ source: String) -> Bool {
        parse(source) != nil
    }

    // MARK: - Parser tests

    @Test func playSound() {
        #expect(parses("""
        on test
          play "Glass"
        end test
        """))
    }

    @Test func playStop() {
        #expect(parses("""
        on test
          play stop
        end test
        """))
    }

    @Test func playSoundWithNotes() {
        #expect(parses("""
        on test
          play "flute" "c d e"
        end test
        """))
    }

    @Test func playSoundWithTempoAndNotes() {
        #expect(parses("""
        on test
          play "flute" tempo 160 "c d e"
        end test
        """))
    }

    @Test func beepAlone() {
        #expect(parses("""
        on test
          beep
        end test
        """))
    }

    @Test func beepWithCount() {
        #expect(parses("""
        on test
          beep 3
        end test
        """))
    }

    @Test func waitDuration() {
        #expect(parses("""
        on test
          wait 5
        end test
        """))
    }

    @Test func waitDurationWithUnit() {
        #expect(parses("""
        on test
          wait 5 seconds
        end test
        """))
    }

    @Test func waitUntilCondition() {
        #expect(parses("""
        on test
          wait until the sound is "done"
        end test
        """))
    }

    // MARK: - Lexer tests

    @Test func playTokenType() {
        var lexer = Lexer(source: "play")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .play)
    }

    @Test func beepTokenType() {
        var lexer = Lexer(source: "beep")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .beep)
    }

    @Test func waitTokenType() {
        var lexer = Lexer(source: "wait")
        let tokens = lexer.tokenize()
        #expect(tokens[0].type == .wait)
    }

    // MARK: - Interpreter tests

    @Test func theSoundPropertyReturnsDone() async {
        // `the sound` should return "done" when no sound is playing.
        // This exercises the global-property path in evaluateProperty
        // (not the evaluateBuiltIn function-call path).
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id

        var field = Part(partType: .field, cardId: cardId, name: "output")
        doc.addPart(field)

        if let idx = doc.cards.firstIndex(where: { $0.id == cardId }) {
            doc.cards[idx].script = """
            on openCard
              put the sound into field "output"
            end openCard
            """
        }

        let dispatcher = MessageDispatcher()
        let result = await runOnLargeStack { [doc, cardId] in dispatcher.dispatch(
            message: "openCard",
            params: [],
            targetId: cardId,
            document: doc,
            currentCardId: cardId
        ) }

        #expect(result.status == .completed)
        let outputField = result.modifiedDocument?.parts.first(where: { $0.name == "output" })
        #expect(outputField?.textContent == "done",
                "the sound should return 'done' when no sound is playing, got '\(outputField?.textContent ?? "nil")'")
    }

    @Test("Runtime dispatch passes real SystemProvider to Birthday Song button")
    func runtimeDispatchRoutesBirthdaySongToSystemProvider() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var button = Part(partType: .button, cardId: cardId, name: "Birthday Song")
        button.script = """
        on mouseUp
          play stop
          play "harpsichord" tempo 120 "g4q g4q a4q g4q c5q b4h"
          wait until the sound is "done"
          play "harpsichord" tempo 120 "g4q g4q a4q g4q d5q c5h"
          wait until the sound is "done"
          play "harpsichord" tempo 120 "g4q g4q g5q e5q c5q b4q a4h"
          wait until the sound is "done"
          play "harpsichord" tempo 120 "f5q f5q e5q c5q d5q c5h"
        end mouseUp
        """
        doc.addPart(button)

        let provider = RecordingSystemProvider()
        let runtime = StackRuntime(
            document: doc,
            configuration: StackRuntimeConfiguration(systemProvider: provider)
        )

        let result = await runtime.dispatchAndWait(
            "mouseUp",
            params: [],
            targetId: button.id,
            currentCardId: cardId
        )

        #expect(result.status == .completed)
        let events = await provider.recordedEvents()
        #expect(events == [
            .stop,
            .playNotes(instrument: "harpsichord", notes: "g4q g4q a4q g4q c5q b4h", tempo: 120),
            .currentSoundName,
            .playNotes(instrument: "harpsichord", notes: "g4q g4q a4q g4q d5q c5h", tempo: 120),
            .currentSoundName,
            .playNotes(instrument: "harpsichord", notes: "g4q g4q g5q e5q c5q b4q a4h", tempo: 120),
            .currentSoundName,
            .playNotes(instrument: "harpsichord", notes: "f5q f5q e5q c5q d5q c5h", tempo: 120)
        ])
    }

    @Test func beepExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          beep
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }

    @Test func playStopExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          play stop
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }

    @Test func waitZeroExecutesWithoutCrash() {
        var lexer = Lexer(source: """
        on test
          wait 0
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
        let interpreter = Interpreter()
        let result = interpreter.execute(handler: handler, params: [], context: context)
        #expect(result.status == .completed)
    }

    // MARK: - Concurrency regression tests
    //
    // Background: when a script called `play "Chime"` (or any other
    // sound where NSSound itself could open the file), Hype crashed
    // inside `SoundPlayer.stop()` with `dispatch_assert_queue_fail`.
    //
    // Root cause: the Interpreter runs on a cooperative async thread,
    // NSSound.stop() synchronously fires NSSoundDelegate's
    // sound(_:didFinishPlaying:) on the same thread, and the @objc
    // bridge for that method is @MainActor in modern AppKit SDKs.
    //
    // Fix: SoundPlayer is @MainActor-isolated, all call sites in the
    // interpreter hop via MainActor.run, and the NSSoundDelegate /
    // AVAudioPlayerDelegate methods are `nonisolated` and dispatch
    // their state mutation through a Task { @MainActor in … } body.
    //
    // These tests exercise the async path and the forbidden synchronous
    // call from a detached non-main task — the latter would no longer
    // even compile if the main-actor isolation was dropped.

    #if canImport(AppKit)
    @Test("SoundPlayer.stop() works when invoked from a detached cooperative task")
    func stopFromDetachedTaskDoesNotCrash() async {
        // Prime the player on main first, then `stop` from a non-main
        // cooperative task. Before the fix this would synchronously
        // trigger the @MainActor delegate assertion and crash.
        await MainActor.run {
            SoundPlayer.shared.stop()
        }
        await Task.detached(priority: .userInitiated) {
            await MainActor.run {
                SoundPlayer.shared.stop()
            }
        }.value
        let finalName = await MainActor.run { SoundPlayer.shared.soundName }
        #expect(finalName == "done")
    }

    @Test("play followed by play on cooperative task doesn't crash (the Chime repro)")
    func playPlayFromCooperativeTaskDoesNotCrash() async {
        // The specific failure path was: script fires `play "Chime"`,
        // which calls SoundPlayer.play → SoundPlayer.stop → NSSound.stop →
        // synchronous NSSoundDelegate callback from a non-main thread.
        // This test mirrors the sequence from a detached task and
        // confirms the whole round-trip now survives.
        await Task.detached(priority: .userInitiated) {
            await MainActor.run {
                SoundPlayer.shared.play(name: "Glass", document: nil)
            }
            await MainActor.run {
                SoundPlayer.shared.play(name: "Pop", document: nil)
            }
            await MainActor.run {
                SoundPlayer.shared.stop()
            }
        }.value
        let name = await MainActor.run { SoundPlayer.shared.soundName }
        #expect(name == "done")
    }

    @Test("play command through full Interpreter async path doesn't crash")
    func playCommandViaAsyncInterpreter() async {
        // Runs a `play "Glass"` handler end-to-end via the async
        // executeAsync path — which is the exact path that hit the
        // Chime crash. The MessageDispatcher uses executeAsync when
        // invoked from async context, so this is the integration-
        // level version of the unit tests above.
        var lexer = Lexer(source: """
        on test
          play "Glass"
          play stop
        end test
        """)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else {
            Issue.record("Parse failed")
            return
        }
        let doc = HypeDocument.newDocument()
        let context = ExecutionContext(
            targetId: doc.cards[0].id,
            currentCardId: doc.cards[0].id,
            document: doc
        )
        let interpreter = Interpreter()
        let result = await Task.detached(priority: .userInitiated) {
            await interpreter.executeAsync(handler: handler, params: [], context: context)
        }.value
        #expect(result.status == .completed,
                "async interpreter should complete play/play stop without the NSSoundDelegate crash")
    }
    #endif
}

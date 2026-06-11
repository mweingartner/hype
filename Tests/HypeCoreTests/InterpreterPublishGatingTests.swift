import Testing
import Foundation
@testable import HypeCore

// MARK: - Counting runtime for publish-gating assertions

/// A minimal `ScriptRuntimeProviding` that counts every `publishDocument` call.
/// No sleep is applied — we want to measure call count, not wall-clock time.
private final class CountingRuntime: ScriptRuntimeProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var publishCount: Int = 0

    func sleep(seconds: TimeInterval) async throws {}
    func navigateToCard(_ cardId: UUID) async {}

    func publishDocument(_ document: HypeDocument) async {
        lock.withLock { publishCount += 1 }
    }

    func enqueueMessage(_ message: String, params: [Value],
                        targetId: UUID, currentCardId: UUID,
                        mouseX: Double, mouseY: Double,
                        scriptContext: ScriptDispatchContext?) async {}
    func startAIRequest(prompt: String, model: String?, callbackMessage: String,
                        owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startMeshyRequest(prompt: String, style: String?, model: String?,
                           callbackMessage: String,
                           owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRemeshRequest(sourceAssetName: String, targetPolycount: Int,
                            callbackMessage: String,
                            owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func startRetextureRequest(sourceAssetName: String, stylePrompt: String,
                               callbackMessage: String,
                               owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func setSpeechListenerActive(_ active: Bool, owner: RuntimeOwnerContext) async throws {}
    func isSpeechListenerActive() async -> Bool { false }
    func startHTTPRequest(_ spec: OutboundHTTPRequestSpec,
                          owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func reply(to requestID: UUID, status: Int, headersText: String, body: String) async throws {}
    func startListener(_ spec: ListenerSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func connectTCP(_ spec: TCPConnectionSpec, owner: RuntimeOwnerContext) async throws -> UUID { UUID() }
    func send(_ data: String, toConnection id: UUID) async throws {}
    func closeConnection(_ id: UUID) async {}
    func stopListener(_ id: UUID) async {}
    func runtimeProperty(objectType: String, id: UUID, property: String,
                         argument: String?) async -> String { "" }
    func pushCardToHistory(_ cardId: UUID) async {}
    func popCardFromHistory() async -> UUID? { nil }
    func recentCards() async -> String { "" }
    func setFoundState(_ state: FoundState?) async {}
    func foundState() async -> FoundState? { nil }
    func setSelectedState(_ state: SelectedState?) async {}
    func selectedState() async -> SelectedState? { nil }
    func setClickState(_ state: ClickState) async {}
    func clickState() async -> ClickState? { nil }

    /// Synchronous snapshot for assertions.
    var count: Int { lock.withLock { publishCount } }
}

// MARK: - Test document helpers

/// Build a minimal document with a button and a named field.
private func makeGatingDoc() -> (doc: HypeDocument, cardId: UUID, btnId: UUID, fieldId: UUID) {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    var btn = Part(partType: .button, cardId: cardId, name: "Btn",
                   left: 10, top: 10, width: 80, height: 30)
    btn.script = ""
    doc.addPart(btn)
    var field = Part(partType: .field, cardId: cardId, name: "output",
                     left: 10, top: 50, width: 200, height: 30)
    field.textContent = ""
    doc.addPart(field)
    return (doc, cardId, btn.id, field.id)
}

/// Run a script via the Interpreter directly (not MessageDispatcher) with the given runtime.
///
/// Uses `runOnLargeStack` because `executeStatement` has deep stack usage that
/// can overflow the cooperative thread pool's default 512 KB stack.
private func runScript(
    _ source: String,
    doc: HypeDocument,
    cardId: UUID,
    targetId: UUID,
    runtime: CountingRuntime
) async -> ExecutionResult {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else {
        return ExecutionResult(status: .error, error: ScriptError(message: "parse error", line: 0, handler: "test"))
    }
    let context = ExecutionContext(
        targetId: targetId,
        currentCardId: cardId,
        document: doc,
        runtimeProvider: runtime
    )
    let interp = Interpreter()
    return await runOnLargeStack {
        interp.execute(handler: handler, params: [], context: context)
    }
}

// MARK: - Publish-gating tests

@Suite("Interpreter publish gating (#0)", .serialized)
struct InterpreterPublishGatingTests {

    // MARK: Pure-compute loops publish few/zero times

    @Test("pure-compute repeat loop publishes zero times")
    func pureComputeLoopPublishesZero() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        // 100-iteration pure-compute loop: add, variable writes, no field mutations.
        let script = """
        on mouseUp
          put 0 into total
          repeat with i = 1 to 100
            add i to total
          end repeat
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // Pre-fix: would have published 200+ times (two statements × 100 iterations
        // + handler body statements).
        // Post-fix: 0 publishes — all statements are pure-compute (variable writes,
        // arithmetic, control flow).
        #expect(runtime.count == 0,
                "pure-compute loop published \(runtime.count) times; expected 0")
    }

    @Test("pure-compute repeat with large count does not publish each iteration")
    func repeatWithLargeCountNoPureComputePublish() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        // A 1000-iteration loop doing pure arithmetic.
        // Each iteration must NOT publish (0 publishes total for this loop).
        let script = """
        on mouseUp
          put 0 into n
          repeat with i = 1 to 1000
            add 1 to n
          end repeat
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // Expect 0 publishes — all pure-compute, no visible effects.
        #expect(runtime.count == 0,
                "pure-compute repeat-with published \(runtime.count) times; expected 0")
    }

    // MARK: Field-write loops publish (animation preserved)

    @Test("loop that writes a field each iteration publishes at least once per write")
    func fieldWriteLoopPublishes() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        // 10-iteration loop that writes a field each time — must publish so
        // the UI can animate (progressive field updates).
        let script = """
        on mouseUp
          repeat with i = 1 to 10
            put i into field "output"
          end repeat
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // We expect at least 10 publishes (one per field write).
        // The upper bound is generous because other visible statements may also publish.
        #expect(runtime.count >= 10,
                "field-write loop published only \(runtime.count) times; expected >= 10 for animation")
    }

    // MARK: lock screen / unlock screen coalescing

    @Test("lock screen suppresses per-statement publishes; unlock screen flushes once")
    func lockScreenCoalescesPublishes() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        // Under lock screen, 5 field writes and 5 variable writes should produce
        // exactly 1 publish at unlock screen, not 5 (or 10).
        let script = """
        on mouseUp
          lock screen
          put "a" into field "output"
          put "b" into field "output"
          put "c" into field "output"
          put "d" into field "output"
          put "e" into field "output"
          unlock screen
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // Exactly 1 publish from unlock screen, none during the locked window.
        #expect(runtime.count == 1,
                "lock screen should coalesce to exactly 1 publish at unlock; got \(runtime.count)")
    }

    @Test("multiple lock/unlock cycles each flush once")
    func multipleLockUnlockCycles() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        let script = """
        on mouseUp
          lock screen
          put "a" into field "output"
          put "b" into field "output"
          unlock screen
          lock screen
          put "c" into field "output"
          unlock screen
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // Two unlock screen calls → exactly 2 publishes.
        #expect(runtime.count == 2,
                "two lock/unlock cycles should produce exactly 2 publishes; got \(runtime.count)")
    }

    @Test("lock screen suppresses pure-compute statements entirely")
    func lockScreenSuppressesPureCompute() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        let script = """
        on mouseUp
          lock screen
          put 0 into total
          repeat with i = 1 to 50
            add i to total
          end repeat
          unlock screen
        end mouseUp
        """
        _ = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // Pure compute under lock screen: exactly 1 flush at unlock.
        #expect(runtime.count == 1,
                "pure-compute under lock screen should produce exactly 1 publish; got \(runtime.count)")
    }

    // MARK: scriptGlobals synchronisation

    @Test("scriptGlobals are synced even when no publish fires")
    func scriptGlobalsSyncedOnPureCompute() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        // Set a global from pure-compute code; verify it is readable from result.
        let script = """
        on mouseUp
          global accumulator
          put 0 into accumulator
          repeat with i = 1 to 10
            add i to accumulator
          end repeat
        end mouseUp
        """
        let result = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        // 1 + 2 + … + 10 = 55
        let globals = result.modifiedDocument?.scriptGlobals ?? [:]
        #expect(globals["accumulator"] == "55",
                "scriptGlobals must sync accumulator=55 even without publish; got \(globals["accumulator"] ?? "nil")")
    }

    // MARK: Cancellation preserved

    @Test("pure-compute loop completes without deadlock (scheduler yields preserved)")
    func pureComputeLoopCompletesCleanly() async {
        let (doc, cardId, btnId, _) = makeGatingDoc()
        let runtime = CountingRuntime()

        let script = """
        on mouseUp
          put 0 into n
          repeat with i = 1 to 100
            add 1 to n
          end repeat
        end mouseUp
        """
        // The loop must complete cleanly — no deadlock from missing yield points.
        let result = await runScript(script, doc: doc, cardId: cardId, targetId: btnId, runtime: runtime)

        #expect(result.status == .completed,
                "expected completed status; got \(result.status)")
    }
}

// MARK: - Variable normalisation tests (#2)

@Suite("Variable name normalisation (#2)", .serialized)
struct VariableNormalisationTests {

    private func evalReturn(_ source: String) -> String? {
        let document = HypeDocument.newDocument()
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
        let context = ExecutionContext(
            targetId: document.cards[0].id,
            currentCardId: document.cards[0].id,
            document: document
        )
        return Interpreter().execute(handler: handler, params: [], context: context).returnValue
    }

    @Test("variable access is case-insensitive")
    func variableCaseInsensitive() {
        let v = evalReturn("""
        on test
          put 42 into MyVar
          return myvar
        end test
        """)
        #expect(v == "42", "expected 42; got \(v ?? "nil")")
    }

    @Test("mixed-case put and get resolve to same variable")
    func mixedCasePutGet() {
        let v = evalReturn("""
        on test
          put "hello" into FOO
          return foo
        end test
        """)
        #expect(v == "hello", "expected hello; got \(v ?? "nil")")
    }

    @Test("global declared in one case is accessible in another case")
    func globalCaseInsensitive() {
        let v = evalReturn("""
        on test
          global Counter
          put 7 into Counter
          global counter
          return counter
        end test
        """)
        #expect(v == "7", "expected 7; got \(v ?? "nil")")
    }

    @Test("global declared as 'x' is set by 'put into X' (case-insensitive)")
    func globalCaseInsensitiveWrite() {
        let v = evalReturn("""
        on test
          global x
          put 1 into x
          put 99 into X
          return x
        end test
        """)
        // `X` lowercases to `x`; since `x` is in globalNames, `put 99 into X`
        // updates the global.  The final value is 99.
        #expect(v == "99", "expected global x=99 after case-insensitive write; got \(v ?? "nil")")
    }

    @Test("constant names are still recognised after normalisation")
    func constantNamesWork() {
        let v = evalReturn("""
        on test
          return EMPTY
        end test
        """)
        #expect(v == "", "expected empty string constant; got \(v ?? "nil")")
    }

    @Test("system property accessed via bare name when no user variable shadows it")
    func systemPropertyBareAccess() {
        // `ticks` is a bare-identifier system property alias.
        // When no local named `ticks` exists it should resolve via evaluateProperty.
        let v = evalReturn("""
        on test
          put the ticks into t
          return t > 0
        end test
        """)
        #expect(v == "true", "expected ticks > 0 to be true; got \(v ?? "nil")")
    }

    @Test("user variable named 'ticks' shadows the system property")
    func userVariableShadowsSystemProperty() {
        let v = evalReturn("""
        on test
          put 9999 into ticks
          return ticks
        end test
        """)
        // The user variable must shadow the system property.
        #expect(v == "9999", "expected user ticks=9999 to shadow system property; got \(v ?? "nil")")
    }
}

// MARK: - Chunk scan fast-path tests (#3)

@Suite("Chunk allocation-free fast path (#3)", .serialized)
struct ChunkFastPathTests {

    private func evalReturn(_ source: String) -> String? {
        let document = HypeDocument.newDocument()
        var lexer = Lexer(source: source)
        let tokens = lexer.tokenize()
        var parser = Parser(tokens: tokens)
        guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
        let context = ExecutionContext(
            targetId: document.cards[0].id,
            currentCardId: document.cards[0].id,
            document: document
        )
        return Interpreter().execute(handler: handler, params: [], context: context).returnValue
    }

    // MARK: char N

    @Test("char 1 of string")
    func char1() {
        let v = evalReturn("on t\n  return char 1 of \"hello\"\nend t")
        #expect(v == "h")
    }

    @Test("char 5 of string")
    func char5() {
        let v = evalReturn("on t\n  return char 5 of \"hello\"\nend t")
        #expect(v == "o")
    }

    @Test("char out of range returns empty")
    func charOutOfRange() {
        let v = evalReturn("on t\n  return char 99 of \"hi\"\nend t")
        #expect(v == "")
    }

    @Test("char last sentinel")
    func charLast() {
        let v = evalReturn("on t\n  return the last char of \"hello\"\nend t")
        #expect(v == "o")
    }

    @Test("char middle sentinel")
    func charMiddle() {
        // "hello" = 5 chars; middle = index 2 (0-based) = "l"
        let v = evalReturn("on t\n  return the middle char of \"hello\"\nend t")
        #expect(v == "l")
    }

    // MARK: word N

    @Test("word 1 of string")
    func word1() {
        let v = evalReturn("on t\n  return word 1 of \"foo bar baz\"\nend t")
        #expect(v == "foo")
    }

    @Test("word 3 of string")
    func word3() {
        let v = evalReturn("on t\n  return word 3 of \"foo bar baz\"\nend t")
        #expect(v == "baz")
    }

    @Test("word 1 of multi-space string")
    func word1MultiSpace() {
        let v = evalReturn("on t\n  return word 2 of \"one  two  three\"\nend t")
        #expect(v == "two")
    }

    @Test("word out of range returns empty")
    func wordOutOfRange() {
        let v = evalReturn("on t\n  return word 99 of \"a b c\"\nend t")
        #expect(v == "")
    }

    @Test("word last sentinel")
    func wordLast() {
        let v = evalReturn("on t\n  return the last word of \"one two three\"\nend t")
        #expect(v == "three")
    }

    // MARK: item N

    @Test("item 1 of comma-delimited string")
    func item1() {
        let v = evalReturn("on t\n  return item 1 of \"a,b,c\"\nend t")
        #expect(v == "a")
    }

    @Test("item 3 of comma-delimited string")
    func item3() {
        let v = evalReturn("on t\n  return item 3 of \"a,b,c\"\nend t")
        #expect(v == "c")
    }

    @Test("item trims whitespace around separator")
    func itemTrimWhitespace() {
        let v = evalReturn("on t\n  return item 2 of \"a, b , c\"\nend t")
        #expect(v == "b")
    }

    @Test("item out of range returns empty")
    func itemOutOfRange() {
        let v = evalReturn("on t\n  return item 99 of \"x,y\"\nend t")
        #expect(v == "")
    }

    @Test("item last sentinel")
    func itemLast() {
        let v = evalReturn("on t\n  return the last item of \"x,y,z\"\nend t")
        #expect(v == "z")
    }

    @Test("item middle sentinel")
    func itemMiddle() {
        // "a,b,c,d,e" → 5 items; middle index = 2 (0-based) = "c"
        let v = evalReturn("on t\n  return the middle item of \"a,b,c,d,e\"\nend t")
        #expect(v == "c")
    }

    @Test("custom itemDelimiter is honoured by item fast path")
    func itemCustomDelimiter() {
        let v = evalReturn("""
        on t
          set the itemDelimiter to "|"
          return item 2 of "alpha|beta|gamma"
        end t
        """)
        #expect(v == "beta", "expected beta with | delimiter; got \(v ?? "nil")")
    }

    // MARK: line N

    @Test("line 1 of multi-line string")
    func line1() {
        // Build the multi-line string using & return & to embed actual carriage returns.
        let v = evalReturn("on t\n  put \"first\" & return & \"second\" & return & \"third\" into s\n  return line 1 of s\nend t")
        #expect(v == "first")
    }

    @Test("line 2 of multi-line string")
    func line2() {
        let v = evalReturn("on t\n  put \"first\" & return & \"second\" & return & \"third\" into s\n  return line 2 of s\nend t")
        #expect(v == "second")
    }

    @Test("line last sentinel")
    func lineLast() {
        let v = evalReturn("on t\n  put \"first\" & return & \"second\" & return & \"third\" into s\n  return the last line of s\nend t")
        #expect(v == "third")
    }

    // MARK: Range form still works (falls through to full-split path)

    @Test("item range form unchanged")
    func itemRangeForm() {
        let v = evalReturn("on t\n  return item 2 to 3 of \"a,b,c,d\"\nend t")
        #expect(v == "b,c")
    }

    @Test("word range form unchanged")
    func wordRangeForm() {
        let v = evalReturn("on t\n  return word 1 to 2 of \"foo bar baz\"\nend t")
        #expect(v == "foo bar")
    }

    // MARK: Large container correctness

    @Test("item N of large container returns correct result")
    func itemNLargeContainer() {
        // Build a 100-item comma-delimited string; fetch item 50.
        let items = (1...100).map(String.init).joined(separator: ",")
        let v = evalReturn("on t\n  return item 50 of \"\(items)\"\nend t")
        #expect(v == "50", "expected 50 for item 50 of 1..100; got \(v ?? "nil")")
    }

    @Test("char N of long string returns correct character")
    func charNLongString() {
        // 500-character string; fetch char 250 (0-indexed: 249th 'a' block).
        let long = String(repeating: "a", count: 249) + "Z" + String(repeating: "a", count: 250)
        let v = evalReturn("on t\n  return char 250 of \"\(long)\"\nend t")
        #expect(v == "Z", "expected Z at position 250; got \(v ?? "nil")")
    }
}

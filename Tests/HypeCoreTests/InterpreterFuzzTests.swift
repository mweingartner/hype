import Foundation
import Testing
@testable import HypeCore

// MARK: - Interpreter fuzz / property / metamorphic harness
//
// An interpreter is the canonical fuzzing target: example-based tests cover the
// cases we thought of, but a grammar fuzzer explores the combinations we didn't.
// This harness has two layers:
//
//   1. A *grammar fuzzer* that generates bounded, valid-ish HypeTalk handlers and
//      asserts two oracle-free properties on every one: the interpreter never
//      crashes/traps (a trap would kill the test process — which is the signal we
//      want), and execution is deterministic (same script twice → same result).
//
//   2. *Metamorphic* relations — equalities that must hold regardless of the
//      operands (x+0 == x, a+b == b+a, a<b == b>a, chunk write/read round-trip,
//      …). Metamorphic testing is the right tool when there is no reference
//      implementation to diff against: we don't assert *what* the answer is, only
//      that two paths that must agree, do.
//
// Everything is driven by a seeded SplitMix64 PRNG, so every run is
// reproducible and CI-deterministic. When a property fails, the failure message
// prints the seed and the generated source so the case can be replayed exactly;
// add that seed to `regressionSeeds` to pin it forever.

// MARK: Deterministic PRNG

/// SplitMix64 — small, fast, reproducible. Seeded per case so failures replay.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func pick<T>(_ xs: [T]) -> T { xs[int(0...(xs.count - 1))] }
    mutating func bool() -> Bool { next() & 1 == 0 }
}

// MARK: Grammar generator
//
// Bounds keep generated scripts terminating and stack-safe: shallow expression
// depth, small loop counts, modest statement counts, no exponential growth.

private struct ScriptGen {
    var rng: SplitMix64
    /// Local variable pool the generated script reads/writes.
    let vars = ["a", "b", "c", "counter", "buf"]
    /// Time/random/mouse sources are EXCLUDED — they would break the determinism
    /// property for legitimate reasons. The fuzzer targets pure language behavior.
    let binaryOps = ["+", "-", "*", "/", "mod", "&", "&&", "<", ">", "<=", ">=", "=", "<>", "is"]
    let chunkKinds = ["char", "word", "item", "line"]
    let constants = ["empty", "space", "quote", "true", "false", "comma", "return"]

    mutating func literal() -> String {
        switch rng.int(0...4) {
        case 0: return String(rng.int(-50...50))                 // integer
        case 1: return String(format: "%.2f", Double(rng.int(-500...500)) / 10.0) // decimal
        case 2: return "\"\(safeString())\""                     // quoted string
        case 3: return rng.pick(constants)
        default: return rng.pick(vars)                           // variable read
        }
    }

    /// Quoted-string contents using only safe characters (no quotes/newlines that
    /// would break lexing; no characters that confuse chunking).
    mutating func safeString() -> String {
        let alphabet = Array("abc def123 XYZ")
        let n = rng.int(0...6)
        return String((0..<n).map { _ in alphabet[rng.int(0...(alphabet.count - 1))] })
    }

    mutating func expr(_ depth: Int) -> String {
        if depth <= 0 { return literal() }
        switch rng.int(0...6) {
        case 0, 1:
            // binary op
            return "(\(expr(depth - 1)) \(rng.pick(binaryOps)) \(expr(depth - 1)))"
        case 2:
            // unary minus (note: `- x`, never `--` which is a comment)
            return "(- \(expr(depth - 1)))"
        case 3:
            // chunk of container
            let idx = rng.int(1...5)
            return "(\(rng.pick(chunkKinds)) \(idx) of \(expr(depth - 1)))"
        case 4:
            // function: length / abs / value
            let fn = rng.pick(["length", "abs", "value"])
            return "\(fn)(\(expr(depth - 1)))"
        default:
            return literal()
        }
    }

    mutating func stmt(_ depth: Int) -> [String] {
        switch rng.int(0...6) {
        case 0:
            return ["put \(expr(2)) into \(rng.pick(vars))"]
        case 1:
            return ["put \(expr(2)) after \(rng.pick(vars))"]
        case 2:
            return ["add \(expr(1)) to \(rng.pick(vars))"]
        case 3:
            return ["subtract \(expr(1)) from \(rng.pick(vars))"]
        case 4 where depth > 0:
            var lines = ["if \(expr(2)) then"]
            lines += block(depth - 1)
            if rng.bool() {
                lines += ["else"]
                lines += block(depth - 1)
            }
            lines += ["end if"]
            return lines
        case 5 where depth > 0:
            // bounded loop: 0..<=8 iterations
            let n = rng.int(1...8)
            var lines = ["repeat with i from 1 to \(n)"]
            lines += block(depth - 1)
            lines += ["end repeat"]
            return lines
        default:
            return ["put \(expr(2)) into \(rng.pick(vars))"]
        }
    }

    mutating func block(_ depth: Int) -> [String] {
        let n = rng.int(1...3)
        return (0..<n).flatMap { _ in stmt(depth) }
    }

    /// A complete `on test … end test` handler that initializes its variables
    /// (so reads are defined) and returns one of them.
    mutating func handler() -> String {
        var lines = ["on test"]
        for v in vars { lines.append("put \(rng.int(-20...20)) into \(v)") }
        lines += block(2)
        lines.append("return \(rng.pick(vars))")
        lines.append("end test")
        return lines.joined(separator: "\n")
    }
}

// MARK: Execution helper

/// Parse + execute a handler synchronously. Returns nil when the source does not
/// parse (a parse error is the validator's job, not a fuzz failure) or has no
/// handler; otherwise returns (status-is-error, returnValue).
@discardableResult
private func execHandler(_ source: String) -> (errored: Bool, value: String)? {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
    let doc = HypeDocument.newDocument()
    let context = ExecutionContext(
        targetId: doc.cards[0].id,
        currentCardId: doc.cards[0].id,
        document: doc
    )
    let result = Interpreter().execute(handler: handler, params: [], context: context)
    if case .error = result.status { return (true, result.returnValue ?? "") }
    return (false, result.returnValue ?? "")
}

/// Evaluate a single expression by wrapping it in `return`. Returns the string
/// value, or nil if it didn't parse/return.
private func evalExpr(_ expression: String) -> String? {
    execHandler("on t\nreturn \(expression)\nend t")?.value
}

// MARK: - Layer 1: grammar fuzzer (no-crash + determinism)

@Suite("Interpreter fuzz — no crash + determinism", .serialized)
struct InterpreterFuzzNoCrashTests {

    /// Seeds that previously surfaced a failure. Add a seed here when the fuzzer
    /// finds a bug so it is pinned as a permanent regression case.
    static let regressionSeeds: [UInt64] = []

    @Test("Generated handlers never crash and are deterministic", arguments: 0..<400)
    func fuzz(seed: Int) {
        var gen = ScriptGen(rng: SplitMix64(seed: UInt64(seed) &* 0x100000001B3 &+ 1))
        let source = gen.handler()

        // Property 1 — no crash / total: execution returns a value or a
        // ScriptError, it never traps. (A trap kills the process; that IS the
        // fuzzer doing its job.) Parse failures are skipped.
        guard let first = execHandler(source) else { return }

        // Property 2 — determinism: same script, same result, every time.
        guard let second = execHandler(source) else {
            Issue.record("seed \(seed): parsed then failed to parse on replay\n\(source)")
            return
        }
        #expect(
            first.errored == second.errored && first.value == second.value,
            "Non-deterministic execution for seed \(seed):\n\(source)\n→ run1=(\(first)) run2=(\(second))"
        )
    }

    @Test("Pinned regression seeds stay green", arguments: InterpreterFuzzNoCrashTests.regressionSeeds)
    func regressions(seed: UInt64) {
        var gen = ScriptGen(rng: SplitMix64(seed: seed))
        let source = gen.handler()
        let a = execHandler(source)
        let b = execHandler(source)
        #expect(a?.value == b?.value && a?.errored == b?.errored, "regression seed \(seed):\n\(source)")
    }
}

// MARK: - Layer 2: metamorphic relations

@Suite("Interpreter metamorphic relations", .serialized)
struct InterpreterMetamorphicTests {

    /// x + 0 == x  (additive identity), for integers.
    @Test("additive identity: x + 0 == x", arguments: 0..<120)
    func additiveIdentity(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 17)
        let x = rng.int(-10_000...10_000)
        #expect(evalExpr("\(x) + 0") == evalExpr("\(x)"), "x+0 != x for x=\(x)")
    }

    /// s & "" == s  (string concat identity).
    @Test("concat identity: s & empty == s", arguments: 0..<120)
    func concatIdentity(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 29)
        let s = String(rng.int(-9_999...9_999))
        #expect(evalExpr("\"\(s)\" & \"\"") == evalExpr("\"\(s)\""), "s&\"\" != s for s=\(s)")
    }

    /// a + b == b + a  and  a * b == b * a  (commutativity), for integers.
    @Test("commutativity: a+b==b+a and a*b==b*a", arguments: 0..<150)
    func commutativity(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 31)
        let a = rng.int(-1_000...1_000), b = rng.int(-1_000...1_000)
        #expect(evalExpr("\(a) + \(b)") == evalExpr("\(b) + \(a)"), "add not commutative: \(a),\(b)")
        #expect(evalExpr("\(a) * \(b)") == evalExpr("\(b) * \(a)"), "mul not commutative: \(a),\(b)")
    }

    /// a < b  ==  b > a  (comparison symmetry), and  (a < b) != (a >= b)
    /// (exhaustive exclusivity), across numeric and lexical operands.
    @Test("comparison symmetry + exclusivity", arguments: 0..<150)
    func comparison(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 37)
        // Mix numeric and short string operands to exercise both compare paths.
        func operand() -> String {
            rng.bool() ? String(rng.int(-50...50)) : "\"\(["apple", "banana", "Cherry", "ok", "OK", ""].randomElement(using: &rng)!)\""
        }
        let a = operand(), b = operand()
        #expect(evalExpr("\(a) < \(b)") == evalExpr("\(b) > \(a)"), "a<b != b>a for \(a),\(b)")
        let lt = evalExpr("\(a) < \(b)"), ge = evalExpr("\(a) >= \(b)")
        #expect(lt != ge, "(a<b) and (a>=b) both \(lt ?? "nil") for \(a),\(b)")
    }

    /// Writing a whitespace-free token into `item N of` a container and reading
    /// the same chunk back returns the token (chunk write/read symmetry).
    @Test("chunk round-trip: put into item N then read item N", arguments: 0..<150)
    func chunkRoundTrip(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 41)
        let count = rng.int(1...6)
        let n = rng.int(1...count)
        let token = "Z\(rng.int(0...9999))"          // whitespace/comma-free
        let initial = (1...count).map { "v\($0)" }.joined(separator: ",")
        let source = """
        on t
          put "\(initial)" into c
          put "\(token)" into item \(n) of c
          return item \(n) of c
        end t
        """
        #expect(execHandler(source)?.value == token, "chunk round-trip failed: item \(n) of \(count), token=\(token)")
    }

    /// length(a & b) == length(a) + length(b) for whitespace-free strings.
    @Test("length is additive over concatenation", arguments: 0..<120)
    func lengthAdditive(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 43)
        func tok() -> String { "x\(rng.int(0...99999))" }
        let a = tok(), b = tok()
        let lhs = evalExpr("length(\"\(a)\" & \"\(b)\")")
        let rhs = evalExpr("length(\"\(a)\") + length(\"\(b)\")")
        #expect(lhs == rhs, "length not additive for \(a),\(b): \(lhs ?? "nil") vs \(rhs ?? "nil")")
    }
}

// MARK: - Layer 3: property-statement fuzzer (control-property-consistency, task 1.8)
//
// Extends the harness with a generator over `set the <name> of <target>
// to <expr>` / `put the <name> of <target> into buf`, driving the
// `PartPropertyRegistry` gate directly. The name pool mixes real
// canonical names, real aliases, near-miss typos, and the bare
// polymorphic words (min/max/value/style/color/…) across a fixture
// document carrying one part per major reachable type. The oracles are
// the same as Layer 1: no crash/trap, and determinism — a `ScriptError`
// (from the strict-SET gate, a wrong-type read, or anything else) is a
// perfectly valid outcome, so long as it's the SAME outcome every time.

/// One property-fuzzable fixture part: its HypeTalk object-type
/// keyword (as accepted by `findPartIndex`/the parser) and its name.
///
/// `.toggle` and `.searchField` are deliberately excluded — HypeTalk's
/// grammar does not currently recognize `toggle "X"` or `searchField
/// "X"` as an object-reference start (Parser.swift's keyword-gated
/// object-ref list omits both), so scripts cannot address a part of
/// either type by `<type> "<name>"` at all. This is a pre-existing,
/// out-of-scope parser gap flagged separately in the Builder's report,
/// not a regression from this change.
private struct PropertyFuzzFixture {
    let objectTypeWord: String
    let partName: String
}

/// Builds a fresh document with one part of every object-ref-reachable
/// major part type, so the generator below can target a wide spread of
/// per-type dispatch cells.
// Visibility note: `PropertyFuzzTypeSpec`/`propertyFuzzTypeSpecs`/
// `propertyFuzzDocument()` are deliberately NOT `private` (file-private
// in Swift) — `CrossSurfacePropertyEquivalenceTests.swift` reuses this
// exact HypeTalk-object-type-keyword mapping for its own registry-driven
// round-trip and cross-surface tests, so the two files stay in lockstep
// on which part types are HypeTalk-object-ref-addressable rather than
// maintaining two independently-drifting copies of the same table.
struct PropertyFuzzTypeSpec {
    let type: PartType
    let objectTypeWord: String
    let partName: String
}

/// The type/keyword/name triples used to build both the fixture
/// document and the (cheap, document-free) fixture list the generator
/// draws targets from.
let propertyFuzzTypeSpecs: [PropertyFuzzTypeSpec] = [
    .init(type: .button, objectTypeWord: "button", partName: "fzButton"),
    .init(type: .field, objectTypeWord: "field", partName: "fzField"),
    .init(type: .shape, objectTypeWord: "shape", partName: "fzShape"),
    .init(type: .webpage, objectTypeWord: "webpage", partName: "fzWebpage"),
    .init(type: .image, objectTypeWord: "image", partName: "fzImage"),
    .init(type: .video, objectTypeWord: "video", partName: "fzVideo"),
    .init(type: .chart, objectTypeWord: "chart", partName: "fzChart"),
    .init(type: .spriteArea, objectTypeWord: "spritearea", partName: "fzSpriteArea"),
    .init(type: .calendar, objectTypeWord: "calendar", partName: "fzCalendar"),
    .init(type: .pdf, objectTypeWord: "pdf", partName: "fzPdf"),
    .init(type: .map, objectTypeWord: "map", partName: "fzMap"),
    .init(type: .colorWell, objectTypeWord: "colorwell", partName: "fzColorWell"),
    .init(type: .stepper, objectTypeWord: "stepper", partName: "fzStepper"),
    .init(type: .slider, objectTypeWord: "slider", partName: "fzSlider"),
    .init(type: .segmented, objectTypeWord: "segmented", partName: "fzSegmented"),
    .init(type: .audioRecorder, objectTypeWord: "recorder", partName: "fzRecorder"),
    .init(type: .scene3D, objectTypeWord: "scene3d", partName: "fzScene3D"),
    .init(type: .musicPlayer, objectTypeWord: "musicplayer", partName: "fzMusicPlayer"),
    .init(type: .pianoKeyboard, objectTypeWord: "pianokeyboard", partName: "fzPianoKeyboard"),
    .init(type: .stepSequencer, objectTypeWord: "stepsequencer", partName: "fzStepSequencer"),
    .init(type: .musicMixer, objectTypeWord: "musicmixer", partName: "fzMusicMixer"),
    .init(type: .appleMusicBrowser, objectTypeWord: "applemusicbrowser", partName: "fzAppleMusicBrowser"),
    .init(type: .musicQueue, objectTypeWord: "musicqueue", partName: "fzMusicQueue"),
    .init(type: .progressView, objectTypeWord: "progressview", partName: "fzProgressView"),
    .init(type: .gauge, objectTypeWord: "gauge", partName: "fzGauge"),
    .init(type: .menu, objectTypeWord: "menu", partName: "fzMenu"),
    .init(type: .divider, objectTypeWord: "divider", partName: "fzDivider"),
]

/// Cheap: just the (objectTypeWord, partName) pairs the generator picks
/// from — no document construction.
private let propertyFuzzFixtures: [PropertyFuzzFixture] = propertyFuzzTypeSpecs.map {
    PropertyFuzzFixture(objectTypeWord: $0.objectTypeWord, partName: $0.partName)
}

/// Builds a fresh document with one part of every object-ref-reachable
/// major part type (`propertyFuzzTypeSpecs`), so the generator can
/// target a wide spread of per-type dispatch cells.
func propertyFuzzDocument() -> HypeDocument {
    var doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    for spec in propertyFuzzTypeSpecs {
        var part = Part(partType: spec.type, cardId: cardId, name: spec.partName, left: 0, top: 0, width: 100, height: 40)
        if spec.type == .field { part.fieldStyle = .rectangle }
        if spec.type == .chart { part.chartData = ChartConfig().toJSON() }
        doc.addPart(part)
    }
    return doc
}

/// Every canonical name + alias in the registry, the bare polymorphic
/// words (which don't have their own descriptor entries — they're
/// resolved by `PartPropertyRegistry`'s internal per-type remap), and
/// a handful of near-miss typos (drop-last-character) of real
/// canonicals — the pool the generator draws property names from.
private let propertyFuzzNamePool: [String] = {
    var names = Set<String>()
    for descriptor in PartPropertyRegistry.descriptors {
        names.insert(descriptor.canonical)
        names.formUnion(descriptor.aliases)
    }
    let bareWords = [
        "value", "on", "min", "max", "step", "loop", "looping", "volume", "autoplay",
        "duration", "tint", "prompt", "total", "items", "decimals", "style", "color",
        "background",
    ]
    names.formUnion(bareWords)
    var typos: [String] = []
    for descriptor in PartPropertyRegistry.descriptors where descriptor.canonical.count > 4 {
        typos.append(String(descriptor.canonical.dropLast()))
    }
    names.formUnion(typos)
    return names.sorted()
}()

/// Parses and executes a single-statement handler against `document`,
/// targeting `cardId`. Mirrors `execHandler` above but threads a real
/// document (with fixture parts) instead of a bare one.
private func execPropertyHandler(_ source: String, document: HypeDocument, cardId: UUID) -> (errored: Bool, value: String)? {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
    let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: document)
    let result = Interpreter().execute(handler: handler, params: [], context: context)
    if case .error = result.status { return (true, result.returnValue ?? "") }
    return (false, result.returnValue ?? "")
}

@Suite("Interpreter fuzz — property statements (registry dispatch)", .serialized)
struct PropertyStatementFuzzTests {
    /// Seeds that previously surfaced a failure. Add a seed here when the
    /// fuzzer finds a bug so it is pinned as a permanent regression case.
    static let regressionSeeds: [UInt64] = []

    /// Generates one `set the <name> of <target> to <expr>` or `put the
    /// <name> of <target> into buf` statement, wrapped in a handler that
    /// returns `buf` (populated only by the `put` form; `""` for `set`).
    private static func generate(seed: UInt64) -> String {
        var rng = SplitMix64(seed: seed)
        let fixture = rng.pick(propertyFuzzFixtures)
        let name = rng.pick(propertyFuzzNamePool)
        let target = "\(fixture.objectTypeWord) \"\(fixture.partName)\""
        if rng.bool() {
            let value: String
            switch rng.int(0...3) {
            case 0: value = "\"\(rng.int(0...999))\""
            case 1: value = "\"\(rng.int(0...999)),\(rng.int(0...999))\""   // pair-shaped (size/loc/rect-ish)
            case 2: value = rng.bool() ? "true" : "false"
            default: value = "\"#\(String(format: "%06X", rng.int(0...0xFFFFFF)))\""  // color-shaped
            }
            return "on t\nset the \(name) of \(target) to \(value)\nreturn buf\nend t"
        }
        return "on t\nput the \(name) of \(target) into buf\nreturn buf\nend t"
    }

    @Test("Generated property statements never crash and are deterministic", arguments: 0..<400)
    func fuzz(seed: Int) {
        let combinedSeed = UInt64(seed) &* 0x2545F4914F6CDD1D &+ 7
        let source = Self.generate(seed: combinedSeed)
        let doc = propertyFuzzDocument()
        let cardId = doc.cards[0].id

        guard let first = execPropertyHandler(source, document: doc, cardId: cardId) else { return }
        guard let second = execPropertyHandler(source, document: doc, cardId: cardId) else {
            Issue.record("seed \(seed): parsed then failed to parse on replay\n\(source)")
            return
        }
        #expect(
            first.errored == second.errored && first.value == second.value,
            "Non-deterministic property dispatch for seed \(seed):\n\(source)\n→ run1=(\(first)) run2=(\(second))"
        )
    }

    @Test("Pinned property-fuzz regression seeds stay green", arguments: PropertyStatementFuzzTests.regressionSeeds)
    func regressions(seed: UInt64) {
        let source = Self.generate(seed: seed)
        let doc = propertyFuzzDocument()
        let cardId = doc.cards[0].id
        let a = execPropertyHandler(source, document: doc, cardId: cardId)
        let b = execPropertyHandler(source, document: doc, cardId: cardId)
        #expect(a?.value == b?.value && a?.errored == b?.errored, "regression seed \(seed):\n\(source)")
    }
}

// MARK: - Layer 4: turtle grammar fuzzer + metamorphic relations (P2, turtle-graphics)
//
// Extends the harness with a generator over the turtle vocabulary (design.md
// D3/D5/D6) — every verb and abbreviation, garbage/negative/huge numeric
// arguments, color-shaped and garbage color arguments, unbalanced
// beginFill/endFill, turtle property gets/sets, and repeat-wrapped bodies —
// plus the metamorphic relations named in the design's test plan. Every run
// starts from a *fresh* `HypeDocument.newDocument()` (no `scriptGlobals`
// seeded) so two executions of the same generated source are directly
// comparable: same error/return outcome AND the same UUID-free part digest.

/// Parses + executes a turtle-flavored handler against a fresh 800×600
/// document. Returns `nil` when the source does not parse (a parse failure
/// is not a fuzz finding); otherwise a UUID/sortKey-free summary: whether
/// the run errored, the error message or return value, and a digest of
/// every part left on the card (name, shape kind, colors, width, and
/// pathData) so two runs can be compared for determinism without false
/// negatives from random identifiers.
private func execTurtleHandler(_ source: String) -> (errored: Bool, message: String, partsDigest: String)? {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
    let doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
    let result = Interpreter().execute(handler: handler, params: [], context: context)

    let errored: Bool
    let message: String
    switch result.status {
    case .error:
        errored = true
        message = result.error?.message ?? ""
    case .cancelled:
        errored = true
        message = "cancelled"
    case .completed, .passed:
        errored = false
        message = result.returnValue ?? ""
    }

    let parts = (result.modifiedDocument?.parts ?? []).filter { $0.cardId == cardId }
    let digest = parts.map { part in
        "\(part.name)|\(part.shapeType.rawValue)|\(part.fillColor)|\(part.strokeColor)|\(part.strokeWidth)|"
            + part.pathData.map { "\($0.x),\($0.y)" }.joined(separator: ";")
    }.joined(separator: "\n")
    return (errored, message, digest)
}

/// Like `execTurtleHandler` but returns the actual `Part` values left on
/// the card, so a test can assert structural standing invariants (names,
/// finiteness, coordinate bounds) that a string digest cannot express.
/// `nil` on a parse failure.
private func execTurtleHandlerParts(_ source: String) -> [Part]? {
    var lexer = Lexer(source: source)
    let tokens = lexer.tokenize()
    var parser = Parser(tokens: tokens)
    guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
    let doc = HypeDocument.newDocument()
    let cardId = doc.cards[0].id
    let context = ExecutionContext(targetId: cardId, currentCardId: cardId, document: doc)
    let result = Interpreter().execute(handler: handler, params: [], context: context)
    return (result.modifiedDocument?.parts ?? doc.parts).filter { $0.cardId == cardId }
}

/// Generates bounded HypeTalk handlers exercising the turtle vocabulary:
/// every verb (long form and abbreviation), tolerant/garbage/huge numeric
/// arguments, valid-name/hex/garbage color arguments, property gets/sets
/// (including the read-only trio), `clean`/`reset turtle`, and — since
/// selection is independent per statement — naturally unbalanced
/// `beginFill`/`endFill` pairs. About half the generated handlers wrap
/// their body in a `repeat N times` loop.
private struct TurtleScriptGen {
    var rng: SplitMix64

    private let zeroArgVerbs = ["home", "penUp", "pu", "penDown", "pd",
                                 "beginFill", "endFill", "clean", "clearScreen", "cs"]
    private let colorArgs = ["\"red\"", "\"blue\"", "\"orange\"", "\"#112233\"",
                              "\"#11223344\"", "\"blurple\"", "\"\""]
    private let settableProperties = ["heading", "penWidth", "penDown", "penColor", "fillColor", "position"]
    private let readableProperties = ["position", "loc", "xcor", "ycor", "heading",
                                       "penDown", "penColor", "penWidth", "fillColor", "filling"]

    mutating func numberArg() -> String {
        switch rng.int(0...5) {
        case 0: return String(rng.int(-2000...2000))
        case 1: return String(format: "%.3f", Double(rng.int(-50000...50000)) / 100.0)
        case 2: return "-\(rng.int(0...5000))"
        case 3: return "\"banana\""                 // non-numeric → coerces to 0
        case 4: return "999999999999"                // huge, in-range for Double
        default: return String(rng.int(0...360))
        }
    }

    mutating func colorArg() -> String { rng.pick(colorArgs) }

    mutating func statement() -> String {
        switch rng.int(0...13) {
        case 0: return "\(rng.pick(["forward", "fd", "back", "bk"])) \(numberArg())"
        case 1: return "\(rng.pick(["right", "rt", "left", "lt"])) \(numberArg())"
        case 2: return "\(rng.pick(["setHeading", "setH"])) \(numberArg())"
        case 3: return "\(rng.pick(["setPos", "setXY"])) \(numberArg()), \(numberArg())"
        case 4: return rng.pick(zeroArgVerbs)
        case 5: return "setPenColor \(colorArg())"
        case 6: return "setFillColor \(colorArg())"
        case 7: return "\(rng.pick(["setPenWidth", "setPenSize"])) \(numberArg())"
        case 8: return "circle \(numberArg())"
        case 9: return "arc \(numberArg()), \(numberArg())"
        case 10: return "dot" + (rng.bool() ? "" : " \(numberArg())")
        case 11:
            let prop = rng.pick(settableProperties)
            let value = prop == "penColor" || prop == "fillColor" ? colorArg()
                : prop == "position" ? "\"\(numberArg()),\(numberArg())\""
                : prop == "penDown" ? (rng.bool() ? "true" : "false")
                : numberArg()
            return "set the \(prop) of the turtle to \(value)"
        case 12:
            // Read-only trio — expected to error; still must never crash.
            return "set the \(rng.pick(["xcor", "ycor", "filling"])) of the turtle to \(numberArg())"
        default:
            return "put the \(rng.pick(readableProperties)) of the turtle into buf"
        }
    }

    mutating func body(_ n: Int) -> [String] {
        (0..<n).map { _ in statement() }
    }

    mutating func handler() -> String {
        var lines = ["on test"]
        let n = rng.int(1...10)
        if rng.bool() {
            let count = rng.int(0...30)
            lines.append("repeat \(count) times")
            lines += body(n)
            lines.append("end repeat")
        } else {
            lines += body(n)
        }
        lines.append("return \"done\"")
        lines.append("end test")
        return lines.joined(separator: "\n")
    }
}

@Suite("Interpreter fuzz — turtle statement family", .serialized)
struct TurtleGrammarFuzzTests {
    /// Seeds that previously surfaced a failure. Add a seed here when the
    /// fuzzer finds a bug so it is pinned as a permanent regression case.
    static let regressionSeeds: [UInt64] = []

    @Test("Generated turtle programs never crash and are deterministic on fresh documents", arguments: 0..<300)
    func fuzz(seed: Int) {
        var gen = TurtleScriptGen(rng: SplitMix64(seed: UInt64(seed) &* 0x9E3779B185EBCA87 &+ 11))
        let source = gen.handler()

        guard let first = execTurtleHandler(source) else { return }
        guard let second = execTurtleHandler(source) else {
            Issue.record("seed \(seed): parsed then failed to parse on replay\n\(source)")
            return
        }
        #expect(
            first.errored == second.errored && first.message == second.message && first.partsDigest == second.partsDigest,
            "Non-deterministic turtle execution for seed \(seed):\n\(source)\n→ run1=(\(first)) run2=(\(second))"
        )
    }

    @Test("Pinned turtle-fuzz regression seeds stay green", arguments: TurtleGrammarFuzzTests.regressionSeeds)
    func regressions(seed: UInt64) {
        var gen = TurtleScriptGen(rng: SplitMix64(seed: seed))
        let source = gen.handler()
        let a = execTurtleHandler(source)
        let b = execTurtleHandler(source)
        #expect(
            a?.errored == b?.errored && a?.message == b?.message && a?.partsDigest == b?.partsDigest,
            "regression seed \(seed):\n\(source)"
        )
    }
}

@Suite("Turtle metamorphic relations", .serialized)
struct TurtleMetamorphicTests {

    @Test("right d then left d restores heading exactly", arguments: 0..<80)
    func rightThenLeftRestoresHeading(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 101)
        let d = rng.int(-1000...1000)
        let result = execTurtleHandler("""
        on test
          right \(d)
          left \(d)
          return the heading of the turtle
        end test
        """)
        #expect(result?.message == "0", "right \(d); left \(d) should restore heading 0, got \(String(describing: result?.message))")
    }

    @Test("fd n then bk n restores position within 1e-9", arguments: 0..<80)
    func forwardThenBackRestoresPosition(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 103)
        let n = rng.int(-3000...3000)
        let result = execTurtleHandler("""
        on test
          fd \(n)
          bk \(n)
          return the position of the turtle
        end test
        """)
        let fields = (result?.message ?? "").split(separator: ",")
        guard fields.count == 2, let x = Double(fields[0]), let y = Double(fields[1]) else {
            Issue.record("could not parse position for n=\(n): \(String(describing: result?.message))")
            return
        }
        #expect(abs(x - 400) < 1e-9 && abs(y - 300) < 1e-9, "fd \(n); bk \(n) drifted to (\(x),\(y))")
    }

    @Test("right (d + 360k) ≡ right d — heading is mod 360", arguments: 0..<80)
    func rightIsModulo360(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 107)
        let d = rng.int(-720...720)
        let k = rng.int(-5...5)
        let a = execTurtleHandler("on test\n  right \(d)\n  return the heading of the turtle\nend test")
        let b = execTurtleHandler("on test\n  right \(d + k * 360)\n  return the heading of the turtle\nend test")
        #expect(a?.message == b?.message, "right \(d) vs right \(d + k * 360): \(String(describing: a?.message)) != \(String(describing: b?.message))")
    }

    @Test("4×(fd L, rt 90) closes the square — one part, first == last vertex", arguments: 0..<40)
    func fourStepSquareCloses(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 109)
        let length = rng.int(1...300)
        guard let result = execTurtleHandler("""
        on test
          repeat 4 times
            fd \(length)
            rt 90
          end repeat
          return "done"
        end test
        """) else {
            Issue.record("square program failed to parse for length \(length)")
            return
        }
        #expect(!result.errored)
        let emittedParts = result.partsDigest.split(separator: "\n")
        #expect(emittedParts.count == 1, "expected exactly one part for length \(length), got \(emittedParts.count)")
        guard let pathField = emittedParts.first?.split(separator: "|").last else { return }
        let vertices = pathField.split(separator: ";")
        #expect(vertices.count == 5, "expected 5 vertices (closed square) for length \(length), got \(vertices.count)")
        #expect(vertices.first == vertices.last, "square did not close for length \(length): \(pathField)")
    }

    @Test("clean twice ≡ clean once — both leave zero parts", arguments: 0..<40)
    func cleanIsIdempotent(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 113)
        let length = rng.int(1...200)
        let once = execTurtleHandler("on test\n  fd \(length)\n  clean\n  return \"done\"\nend test")
        let twice = execTurtleHandler("on test\n  fd \(length)\n  clean\n  clean\n  return \"done\"\nend test")
        #expect(once?.partsDigest == twice?.partsDigest, "clean once vs twice diverged for length \(length)")
        #expect(twice?.partsDigest.isEmpty == true, "clean should leave zero turtle parts")
    }

    @Test("arc 360, r ≡ circle r on the HypeTalk surface (metamorphic — full arc is a circle)", arguments: 0..<40)
    func arc360EqualsCircle(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 127)
        let r = rng.int(1...400)
        let circle = execTurtleHandler("on test\n  circle \(r)\n  return \"done\"\nend test")
        let arc = execTurtleHandler("on test\n  arc 360, \(r)\n  return \"done\"\nend test")
        #expect(circle?.partsDigest == arc?.partsDigest,
                "arc 360, \(r) must draw the same part as circle \(r):\n  circle=\(circle?.partsDigest ?? "nil")\n  arc=\(arc?.partsDigest ?? "nil")")
    }
}

// MARK: - Standing invariants over the turtle fuzz corpus
//
// The design's test plan names harness-wide invariants; the determinism
// fuzzer above asserts none of them (it only compares a run against itself),
// so this suite generates the same bounded turtle programs and checks the
// structural invariants the ENGINE actually guarantees on whatever parts they
// leave behind:
//
//   * every emitted part carries a reserved-prefix name (its accessible
//     identity — the applier never emits an unnamed part), and
//   * every pathData vertex is FINITE (no NaN/±Inf ever reaches a part,
//     even under garbage/huge/non-finite arguments).
//
// NOTE (reported to the pipeline, not asserted here): the design lists a
// "pathData within ±1,000,000" invariant, but the engine clamps only the
// turtle *position* (`move`/stroke vertices) to ±positionLimit — `circle`/
// `arc` vertices are `center ± radius·trig` with an UNCLAMPED radius, so a
// pathological `circle 999999999999` yields finite pathData far outside
// ±1,000,000. Asserting the ±1e6 bound on curve vertices would test the spec
// wording rather than the implementation, so this suite asserts finiteness
// (which genuinely holds) and the observation is surfaced in the Test report.

@Suite("Turtle standing invariants — reserved names + finite geometry", .serialized)
struct TurtleStandingInvariantFuzzTests {

    @Test("every emitted part is reserved-prefix-named with finite pathData", arguments: 0..<200)
    func emittedPartsHonorStandingInvariants(seed: Int) {
        var gen = TurtleScriptGen(rng: SplitMix64(seed: UInt64(seed) &* 0x9E3779B185EBCA87 &+ 29))
        let source = gen.handler()
        guard let parts = execTurtleHandlerParts(source) else { return } // parse failure isn't a fuzz finding

        for part in parts {
            #expect(TurtlePartApplier.namePrefixes.contains { part.name.hasPrefix($0) },
                    "seed \(seed): part \"\(part.name)\" lacks a reserved turtle prefix\n\(source)")
            for point in part.pathData {
                #expect(point.x.isFinite && point.y.isFinite,
                        "seed \(seed): non-finite vertex (\(point.x),\(point.y)) in \(part.name)\n\(source)")
            }
        }
    }
}

// MARK: - Security A2 (parser robustness) + C13 (bounded-loop DoS)

@Suite("Security — parser robustness (A2) and bounded loops (C13)", .serialized)
struct TurtleSecurityRobustnessTests {

    /// A2 + B1: deeply-nested parenthesized expressions must not crash the
    /// process (a native stack overflow would kill the whole test run —
    /// that IS the failure mode this guards). Historically 500 levels was
    /// an empirically safe margin on an 8 MB thread stack for this
    /// recursive-descent parser (probed locally: 700 levels parses
    /// cleanly, 800 traps) — see the Builder's report for the deviation
    /// from the design's "thousands" example figure.
    ///
    /// Security B1 (fix) added `Parser.maxExpressionDepth` (256), an
    /// internal recursion-depth cap on the parser's own expression-parsing
    /// entry points. Each level of parenthesized nesting costs 4 depth
    /// increments (one through each of `parseExpression`/`parseNot`/
    /// `parseUnary`/`parsePrimary`), so the cap now trips around paren
    /// level ~64 — long before 500. 500 levels therefore no longer parses
    /// (as it silently did pre-B1, via a swallowed `try?`); it refuses
    /// with a clean `ParseError` instead. That is the correct, INTENDED
    /// post-fix behavior — a crash is still the only unacceptable outcome.
    @Test("Deeply-nested expression (500 parens) refuses with a clean ParseError, not a crash")
    func deeplyNestedExpressionNoCrash() async {
        let nested = String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)
        let source = "on test\n  return \(nested)\nend test"
        let threw = await runOnLargeStack { () -> Bool in
            var lexer = Lexer(source: source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            do {
                _ = try parser.parse()
                return false
            } catch is ParseError {
                return true
            } catch {
                return false
            }
        }
        #expect(threw, "500 levels of paren nesting must refuse with ParseError under the B1 depth cap, not succeed silently or crash")
    }

    /// B1 control: nesting comfortably under the parser's depth cap must
    /// still parse — the cap guards against pathological input, not
    /// ordinary scripts. 40 levels of paren nesting costs 40 * 4 = 160
    /// depth increments, safely under the 256 cap.
    @Test("Moderately-nested expression (40 parens) still parses successfully")
    func moderatelyNestedExpressionStillParses() async {
        let nested = String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40)
        let source = "on test\n  return \(nested)\nend test"
        let parsed = await runOnLargeStack { () -> Bool in
            var lexer = Lexer(source: source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            return (try? parser.parse()) != nil
        }
        #expect(parsed, "40 levels of paren nesting is well under the B1 depth cap and must still parse")
    }

    /// A2: a ~64 KB turtle program (breadth, not depth — thousands of
    /// sequential statements) must not crash and must run to completion.
    @Test("~64 KB turtle program does not crash and runs to completion")
    func maxLengthProgramNoCrash() async {
        let line = "forward 1\n"
        let repeatCount = (64 * 1024) / line.utf8.count + 10
        let body = String(repeating: line, count: repeatCount)
        let source = "on test\n\(body)return \"done\"\nend test"
        #expect(source.utf8.count > 64 * 1024)

        let outcome = await runOnLargeStack { () -> (errored: Bool, message: String)? in
            var lexer = Lexer(source: source)
            let tokens = lexer.tokenize()
            var parser = Parser(tokens: tokens)
            guard let script = try? parser.parse(), let handler = script.handlers.first else { return nil }
            let doc = HypeDocument.newDocument()
            let context = ExecutionContext(targetId: doc.cards[0].id, currentCardId: doc.cards[0].id, document: doc)
            let result = Interpreter().execute(handler: handler, params: [], context: context)
            if case .error = result.status { return (true, result.error?.message ?? "") }
            return (false, result.returnValue ?? "")
        }
        #expect(outcome != nil, "the 64 KB program failed to parse")
        #expect(outcome?.message == "done", "expected the run to complete normally, got \(String(describing: outcome))")
    }

    /// C13: an empty-body counted loop with a huge literal count must
    /// terminate via the instruction-limit guard, not spin unbounded.
    /// Mirrors the pre-existing `ScriptNumericSafetyTests` huge-count case
    /// (which exits via `exit repeat` on iteration 1 and so never exercised
    /// an *empty* body) — this is the gap Security C13 closes.
    @Test("repeat 1000000000 times / end repeat (empty body) terminates with the instruction-limit error")
    func hugeCountEmptyBodyRepeatIsBounded() {
        let result = execTurtleHandler("""
        on test
          repeat 1000000000 times
          end repeat
          return "unreachable"
        end test
        """)
        #expect(result?.errored == true)
        #expect(result?.message == "Instruction limit exceeded")
    }

    /// C13: the same guard on `.repeatWith` — a huge empty-body counted
    /// range must also terminate, not just the `repeat N times` form.
    @Test("repeat with i = 1 to 999999999 / end repeat (empty body) terminates with the instruction-limit error")
    func hugeRangeEmptyBodyRepeatWithIsBounded() {
        let result = execTurtleHandler("""
        on test
          repeat with i = 1 to 999999999
          end repeat
          return "unreachable"
        end test
        """)
        #expect(result?.errored == true)
        #expect(result?.message == "Instruction limit exceeded")
    }

    // MARK: - Security B1 (parser-internal recursion-depth cap)
    //
    // The A2 pre-parse token-nesting guard (`nestingDepthRefusal`, above
    // `TurtleProgramValidator`) only counts `(`/`)` and `if`/`repeat`
    // nesting over the RAW token stream. It cannot see every construct
    // that makes the real recursive-descent `Parser` recurse: bare
    // prefix-operator chains (`- - - 1`, `not not not x`, `await await
    // x`), and chunk `of` chains (`item 1 of item 1 of … x`) use no
    // `(`/`)`/`if`/`repeat` token at all, so the A2 counter never moves
    // for them. Security B1 closes this gap with an internal
    // recursion-depth cap inside the parser itself
    // (`Parser.maxExpressionDepth`, 256) so ANY pathological nesting —
    // regardless of which grammar construct produces it — refuses with a
    // clean `ParseError` (which `TurtleProgramValidator.validate`
    // translates to a `.refused` E9 verdict) instead of overflowing the
    // native stack. Every case below drives the attack THROUGH
    // `TurtleProgramValidator.validate(program:)`, the real
    // `draw_with_turtle` entry point — not the raw parser — so this is
    // the same code path the AI tool actually exercises.

    /// Asserts `TurtleProgramValidator.validate(program:)` refuses
    /// `program` cleanly (`.refused`) — never crashing and never
    /// returning `.ok`. Runs on a real 8 MB-stack thread (matching the
    /// macOS main thread) so a regression in the depth cap crashes the
    /// test process loudly instead of silently passing on Swift Testing's
    /// smaller cooperative-thread stack.
    private func assertValidatorRefusesCleanly(_ program: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        let verdict = await runOnLargeStack { () -> TurtleProgramValidator.Verdict in
            TurtleProgramValidator.validate(program: program)
        }
        guard case .refused = verdict else {
            Issue.record("expected .refused, got \(verdict)", sourceLocation: sourceLocation)
            return
        }
    }

    /// Asserts `TurtleProgramValidator.validate(program:)` accepts
    /// `program` (`.ok`) — the control side of the B1 fix: the parser's
    /// new depth cap must not reject ordinary, shallow, legitimate turtle
    /// programs.
    private func assertValidatorAccepts(_ program: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        let verdict = await runOnLargeStack { () -> TurtleProgramValidator.Verdict in
            TurtleProgramValidator.validate(program: program)
        }
        guard case .ok = verdict else {
            Issue.record("expected .ok, got \(verdict)", sourceLocation: sourceLocation)
            return
        }
    }

    /// B1 crash vector 1: a bare unary-minus prefix chain — no
    /// parenthesis, no `if`/`repeat` — so the A2 pre-scan's token-nesting
    /// counter never moves. 512 is 2x the parser's 256-level cap.
    @Test("B1: a 512-deep bare `-` prefix chain refuses cleanly through validate(), not a crash")
    func bareMinusChainThroughValidatorRefusesCleanly() async {
        let program = "forward " + String(repeating: "- ", count: 512) + "1"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 crash vector 2a: a bare `not` prefix chain — same blind spot as
    /// the minus chain.
    @Test("B1: a 512-deep `not` chain refuses cleanly through validate(), not a crash")
    func notChainThroughValidatorRefusesCleanly() async {
        let program = "forward " + String(repeating: "not ", count: 512) + "true"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 crash vector 2b: the `!` spelling of the same `not` chain — the
    /// lexer maps `!` directly to the `.not` token, so this exercises the
    /// identical recursive path through `parseNot`.
    @Test("B1: a 512-deep `!` chain refuses cleanly through validate(), not a crash")
    func bangChainThroughValidatorRefusesCleanly() async {
        let program = "forward " + String(repeating: "! ", count: 512) + "true"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 crash vector 3: a chunk `of` chain — `parsePrimary` recurses
    /// into itself for the chunk's `source` sub-expression, entirely
    /// inside `parsePrimary`, never touching a `(`/`)`/`if`/`repeat`
    /// token the A2 pre-scan counts.
    @Test("B1: a 512-deep `item 1 of` chunk chain refuses cleanly through validate(), not a crash")
    func chunkOfChainThroughValidatorRefusesCleanly() async {
        let program = "forward " + String(repeating: "item 1 of ", count: 512) + "x"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 crash vector 4: deeply nested parentheses. 100 levels stays
    /// under the A2 pre-scan's own 200-level `(`/`)` cap (so this program
    /// reaches the real parser instead of being refused before it), but
    /// exceeds the parser-internal B1 cap — one level of paren nesting
    /// costs 4 depth increments (one each through `parseExpression`,
    /// `parseNot`, `parseUnary`, `parsePrimary`), so 100 levels reaches
    /// depth 400, well past the 256 cap. This isolates the NEW B1
    /// guard specifically, independent of the pre-existing A2 pre-scan
    /// (which has its own dedicated coverage in
    /// `TurtleCrossSurfaceEquivalenceTests.deeplyNestedProgramRefusesCleanly`).
    @Test("B1: 100 levels of nested parens (under A2's 200-cap) still refuses cleanly through validate()")
    func nestedParensThroughValidatorRefusesCleanly() async {
        let nested = String(repeating: "(", count: 100) + "1" + String(repeating: ")", count: 100)
        let program = "forward \(nested)"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 crash vector 5: nested function-call arguments. Each `f(` opens
    /// a fresh `parseExpression()` descent for the argument list — the
    /// same 4-increments-per-level cost as explicit parens (both funnel
    /// through `parsePrimary`'s function-call branch into
    /// `parseExpression()`). 100 levels stays under A2's 200-level
    /// `(`/`)` cap (a call's open paren is lexically indistinguishable
    /// from a grouping paren) but exceeds B1's effective ~64-level
    /// threshold, again isolating the new parser-internal guard.
    @Test("B1: 100-deep nested function calls (under A2's 200-cap) still refuse cleanly through validate()")
    func nestedFunctionCallsThroughValidatorRefusesCleanly() async {
        let nested = String(repeating: "f(", count: 100) + "1" + String(repeating: ")", count: 100)
        let program = "forward \(nested)"
        await assertValidatorRefusesCleanly(program)
    }

    /// B1 control: ordinary shallow turtle programs — the kind
    /// `draw_with_turtle` is actually meant to accept — must still
    /// validate `.ok` after the depth cap lands.
    @Test("B1 control: `forward -50` still validates .ok")
    func shallowNegativeNumberStillValidatesOk() async {
        await assertValidatorAccepts("forward -50")
    }

    /// B1 control: shallow parenthesized arithmetic still validates `.ok`.
    @Test("B1 control: `forward (2 + 3) * 4` still validates .ok")
    func shallowParenthesizedArithmeticStillValidatesOk() async {
        await assertValidatorAccepts("forward (2 + 3) * 4")
    }

    /// B1 control: a property `set` on the turtle still validates `.ok`.
    @Test("B1 control: `set the heading of the turtle to 45` still validates .ok")
    func shallowPropertySetStillValidatesOk() async {
        await assertValidatorAccepts("set the heading of the turtle to 45")
    }
}

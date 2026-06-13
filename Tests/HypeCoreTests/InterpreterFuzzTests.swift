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

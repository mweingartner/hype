import Foundation
import Testing
@testable import HypeCore

/// Pins the `Any`→`HypeMCPJSONValue` number/boolean bridging in
/// `HypeMCPJSONValue.init(any:)`. `JSONSerialization` returns `NSNumber` for
/// BOTH JSON numbers and JSON booleans, and `NSNumber(0)`/`NSNumber(1)` satisfy
/// Swift's `as? Bool` cast, so a numeric `0`/`1` (the default for many `Part`
/// fields) used to be mis-typed as a JSON boolean — breaking a strict
/// `JSONDecoder().decode(Part.self, …)` of `hype_get_object` output. The fix
/// disambiguates via `CFBoolean` identity.
/// See `openspec/changes/fix-mcp-json-number-bridging/design.md`.
@Suite("MCP JSON codec — number/boolean bridging")
@MainActor
struct MCPJSONCodecTests {

    // MARK: - init(any:) direct typing

    @Test("numeric 0 and 1 (from JSONSerialization) are .number, not .bool")
    func numericZeroOneViaJSONSerialization() throws {
        let any = try JSONSerialization.jsonObject(with: Data(#"{"a":0,"b":1,"c":42}"#.utf8))
        let obj = try #require(HypeMCPJSONValue(any: any).objectValue)
        for key in ["a", "b", "c"] {
            guard case .number = obj[key] else {
                Issue.record("\(key) should be .number, got \(String(describing: obj[key]))")
                continue
            }
        }
    }

    @Test("JSON booleans (from JSONSerialization) are .bool")
    func boolsViaJSONSerialization() throws {
        let any = try JSONSerialization.jsonObject(with: Data(#"{"t":true,"f":false}"#.utf8))
        let obj = try #require(HypeMCPJSONValue(any: any).objectValue)
        #expect(obj["t"] == .bool(true))
        #expect(obj["f"] == .bool(false))
    }

    @Test("native Swift Bool/Int/Double boxed directly as Any type correctly (Security-plan advisory)")
    func nativeBoxedAny() {
        #expect(HypeMCPJSONValue(any: true) == .bool(true))
        #expect(HypeMCPJSONValue(any: false) == .bool(false))
        #expect(HypeMCPJSONValue(any: 0) == .number(0))
        #expect(HypeMCPJSONValue(any: 1) == .number(1))
        #expect(HypeMCPJSONValue(any: 3.5) == .number(3.5))
    }

    /// A different `NSNumber` *subclass* than `JSONSerialization` produces
    /// (`__NSCFNumber`/`__NSCFBoolean`), exercised directly: `NSDecimalNumber`
    /// is still an `NSNumber`, still hits the `case let value as NSNumber`
    /// branch, and — critically — must NOT satisfy the `CFBoolean` identity
    /// check for `0`/`1` any more than a plain `NSNumber` does. Pins that the
    /// disambiguation is by CFBoolean *identity*, not by numeric value.
    @Test("NSDecimalNumber (a distinct NSNumber subclass) types as .number, not .bool, including at 0 and 1")
    func decimalNumberTypesAsNumberNotBool() {
        #expect(HypeMCPJSONValue(any: NSDecimalNumber(string: "12.34")) == .number(12.34))
        for text in ["0", "1", "-1", "255.5"] {
            guard case .number = HypeMCPJSONValue(any: NSDecimalNumber(string: text)) else {
                Issue.record(".number expected for NSDecimalNumber(\(text))")
                continue
            }
        }
    }

    // MARK: - Property/fuzz: both construction paths agree (seeded, reproducible)

    @Test("fuzz: values type identically via JSONSerialization vs native boxing, correctly bool vs number")
    func fuzzBothConstructionPathsAgree() throws {
        struct FuzzCase { let json: String; let native: Any; let wantBool: Bool }
        var cases: [FuzzCase] = [
            FuzzCase(json: "true", native: true, wantBool: true),
            FuzzCase(json: "false", native: false, wantBool: true),
        ]
        for n in [0, 1, -1, 2, 255, 1_000_000, -1_000_000] {
            cases.append(FuzzCase(json: "\(n)", native: n, wantBool: false))
        }
        for d in [0.0, 1.0, -1.0, 0.5, 3.14159, 1e10] {
            cases.append(FuzzCase(json: "\(d)", native: d, wantBool: false))
        }
        for c in cases {
            // (a) via JSONSerialization (NSNumber-backed) …
            let arr = try #require(try JSONSerialization.jsonObject(with: Data("[\(c.json)]".utf8)) as? [Any])
            let viaJSON = HypeMCPJSONValue(any: arr[0])
            // … (b) via a directly-boxed native Swift value (the debugPartSummary path).
            let viaNative = HypeMCPJSONValue(any: c.native)
            #expect(viaJSON == viaNative, "typing diverged for \(c.json)")
            if c.wantBool {
                guard case .bool = viaJSON else { Issue.record(".bool expected for \(c.json)"); continue }
            } else {
                guard case .number = viaJSON else { Issue.record(".number expected for \(c.json)"); continue }
            }
        }
    }

    /// Widens the fixed-case fuzz above to the edges Security's Conditions
    /// for Builder called out but the Builder's pass didn't reach: `Int.max`/
    /// `Int.min` (an `NSNumber` at the boundary of exact `Int64` bridging),
    /// and large-magnitude negative doubles (the existing pass had `-1.0`
    /// but nothing past it). Same two-construction-path agreement oracle.
    @Test("fuzz: Int.max/min and large-magnitude negative doubles type as .number identically via both construction paths")
    func edgeScalarsTypeAsNumberBothPaths() throws {
        struct EdgeCase { let json: String; let native: Any }
        let cases: [EdgeCase] = [
            EdgeCase(json: "\(Int.max)", native: Int.max),
            EdgeCase(json: "\(Int.min)", native: Int.min),
            EdgeCase(json: "-3.14159", native: -3.14159),
            EdgeCase(json: "-1000000000.5", native: -1_000_000_000.5),
            EdgeCase(json: "-0.0001", native: -0.0001),
        ]
        for c in cases {
            let arr = try #require(try JSONSerialization.jsonObject(with: Data("[\(c.json)]".utf8)) as? [Any])
            let viaJSON = HypeMCPJSONValue(any: arr[0])
            let viaNative = HypeMCPJSONValue(any: c.native)
            #expect(viaJSON == viaNative, "typing diverged for \(c.json)")
            guard case .number = viaJSON else {
                Issue.record(".number expected for \(c.json), got \(viaJSON)")
                continue
            }
        }
    }

    // MARK: - Property: seeded nested structures (metamorphic + determinism)

    /// SplitMix64 — small, fast, reproducible. Seeded per case so a failure
    /// replays exactly. Mirrors the PRNG already established in
    /// `InterpreterFuzzTests.swift` (file-private there, so re-declared here
    /// rather than shared).
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
    }

    /// Generates a bounded-depth value both as a native `Any` tree (arrays/
    /// dictionaries of `Bool`/`Int`/`Double`, boxed directly the way
    /// `debugPartSummary` does) and as the textually
    /// equivalent JSON, so the two `init(any:)` construction paths can be
    /// diffed against each other with no third oracle needed. Deliberately
    /// weights leaves toward exactly `0`/`1` — the bug's exact trigger value
    /// — nested inside arrays/objects rather than at the top level, which
    /// the existing fuzz/example tests do not exercise.
    ///
    /// `forceContainer` MUST be `true` at the root call: `JSONSerialization
    /// .jsonObject(with:)` (called with the default options, matching the
    /// real `codableJSONValue` call site) rejects a top-level JSON
    /// *fragment* (a bare `true`/`5`/`3.5` with no enclosing `[]`/`{}`) —
    /// only nested leaves may be scalars.
    private static func generateNestedValue(
        depth: Int,
        rng: inout SplitMix64,
        forceContainer: Bool = false
    ) -> (native: Any, json: String) {
        func leaf() -> (native: Any, json: String) {
            switch rng.int(0...4) {
            case 0: return (true, "true")
            case 1: return (false, "false")
            case 2:
                let n = rng.int(0...1) // the exact bridging trigger
                return (n, "\(n)")
            case 3:
                let n = rng.int(-1000...1000)
                return (n, "\(n)")
            default:
                let d = Double(rng.int(-1000...1000)) / 8.0
                return (d, "\(d)")
            }
        }
        guard depth > 0 else { return leaf() }
        switch forceContainer ? rng.int(2...3) : rng.int(0...3) {
        case 0, 1:
            return leaf()
        case 2:
            let count = rng.int(1...3)
            var natives: [Any] = []
            var jsonParts: [String] = []
            for _ in 0..<count {
                let (nativeValue, json) = generateNestedValue(depth: depth - 1, rng: &rng)
                natives.append(nativeValue)
                jsonParts.append(json)
            }
            return (natives, "[\(jsonParts.joined(separator: ","))]")
        default:
            let count = rng.int(1...3)
            var dict: [String: Any] = [:]
            var jsonParts: [String] = []
            for index in 0..<count {
                let key = "k\(index)"
                let (nativeValue, json) = generateNestedValue(depth: depth - 1, rng: &rng)
                dict[key] = nativeValue
                jsonParts.append("\"\(key)\":\(json)")
            }
            return (dict, "{\(jsonParts.joined(separator: ","))}")
        }
    }

    /// Seeds that previously surfaced a divergence. Pin a failing seed here
    /// (as a permanent regression case) if this fuzzer ever finds one.
    /// `nonisolated`: a `Test` macro's `arguments:` is evaluated outside
    /// main-actor isolation, and this is an immutable `[UInt64]` literal —
    /// safe to read from any context.
    nonisolated static let nestedStructureRegressionSeeds: [UInt64] = []

    /// Metamorphic relation: a nested tree of bools/numbers built two ways —
    /// (a) native Swift values boxed directly as `Any` (the
    /// `debugPartSummary` call-site shape), and (b) the
    /// textually-equivalent JSON parsed via `JSONSerialization` (the
    /// `codableJSONValue` call-site shape) — MUST type identically through
    /// `init(any:)`, at every depth, not just at the top level. Also asserts
    /// determinism (same input, reconstructed, gives an identical result)
    /// and totality (bounded depth/breadth guarantees termination; the
    /// generator itself proves no crash by not trapping across 80 seeds).
    @Test("property: seeded nested bool/number trees agree across native-boxed and JSONSerialization construction, and are deterministic", arguments: 0..<80)
    func nestedStructuresAgreeAcrossConstructionPathsAndAreDeterministic(seed: Int) throws {
        var rng = SplitMix64(seed: UInt64(seed) &* 0x2545F4914F6CDD1D &+ 11)
        let (native, json) = Self.generateNestedValue(depth: 3, rng: &rng, forceContainer: true)

        let viaNative = HypeMCPJSONValue(any: native)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let viaJSON = HypeMCPJSONValue(any: parsed)
        #expect(viaNative == viaJSON, "seed \(seed): native/JSON typing diverged for \(json)")

        // Determinism: reconstructing from the same native input twice
        // yields an equal result both times.
        let viaNativeAgain = HypeMCPJSONValue(any: native)
        #expect(viaNative == viaNativeAgain, "seed \(seed): non-deterministic construction for \(json)")
    }

    @Test("property: pinned nested-structure regression seeds stay green", arguments: MCPJSONCodecTests.nestedStructureRegressionSeeds)
    func nestedStructureRegressions(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let (native, json) = Self.generateNestedValue(depth: 3, rng: &rng, forceContainer: true)
        let viaNative = HypeMCPJSONValue(any: native)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let viaJSON = HypeMCPJSONValue(any: parsed)
        #expect(viaNative == viaJSON, "regression seed \(seed): \(json)")
    }

    // MARK: - Real Part round-trip through hype_get_object (the bug's actual scenario)

    @Test("a Part with numeric fields at 0/1 round-trips get_object → strict Part decode")
    func partRoundTripThroughGetObject() async throws {
        var document = HypeDocument.newDocument(name: "MCP JSON codec")
        let cardId = try #require(document.sortedCards.first?.id)
        var part = Part(partType: .button, cardId: cardId, name: "b", left: 10, top: 20, width: 80, height: 30)
        // The exact 0/1 numeric values the bug mis-typed as JSON booleans.
        part.rotation = 0
        part.strokeWidth = 1
        part.family = 1
        document.addPart(part)
        let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

        let getResult = await backend.callTool(
            name: "hype_get_object",
            arguments: ["object_type": .string("part"), "id_or_name": .string(part.id.uuidString)]
        )
        let objectValue = try #require(getResult.objectValue?["object"])
        // Encode the returned HypeMCPJSONValue and strict-decode a Part — the
        // exact GET→decode step that threw before the fix (a numeric 0/1 typed
        // as a JSON bool makes `rotation: Double` fail to decode from `false`).
        let decoded = try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(objectValue))
        #expect(decoded.id == part.id)
        #expect(decoded.rotation == 0)
        #expect(decoded.strokeWidth == 1)
        #expect(decoded.family == 1)
    }

    /// Metamorphic/integration pass extending the single-`.button` round
    /// trip above to every `PartType` (enum exhaustiveness — Test category
    /// 4). `Part` is a flat product type with no per-`partType` conditional
    /// `Codable` encoding — every stored property exists, at its
    /// `init(partType:...)` default, regardless of `partType` — so the
    /// all-default construction here already carries the same 0/1-heavy
    /// field set the single-Part test pins (`videoPlayRate=1`,
    /// `controlValue=0`, `pdfCurrentPage=1`, `gaugeValue=0`, `gaugeMax=1.0`,
    /// `progressTotal=1.0`, `musicPosition=0`, …) for every generated part.
    /// This guards the same bug from ever resurfacing in a form that only
    /// reproduces for a specific `partType` (e.g. a future per-type
    /// conditional-encoding refactor).
    ///
    /// `.toggle`, `.menu`, `.link`, and `.searchField` are deliberately
    /// NOT asserted to decode back to themselves: `Part.init(from:)`'s
    /// documented "Legacy-PartType migration" (`Part.swift`) rewrites
    /// these four to `.button`/`.button`/`.button`/`.field` on EVERY
    /// decode, not only for old documents — pre-existing, intentional
    /// behavior wholly unrelated to this fix. (First discovered as an
    /// apparent regression by this exact test — worth pinning the
    /// expectation explicitly so it is never mistaken for one again.)
    @Test("every PartType round-trips hype_get_object → strict Part decode with its all-default (many 0/1) numeric fields")
    func everyPartTypeRoundTripsThroughGetObject() async throws {
        let migratesTo: [PartType: PartType] = [
            .toggle: .button,
            .menu: .button,
            .link: .button,
            .searchField: .field,
        ]
        for partType in PartType.allCases {
            var document = HypeDocument.newDocument(name: "MCP JSON codec — \(partType.rawValue)")
            let cardId = try #require(document.sortedCards.first?.id)
            let part = Part(
                partType: partType,
                cardId: cardId,
                name: "p-\(partType.rawValue)",
                left: 10, top: 20, width: 80, height: 30
            )
            document.addPart(part)
            let backend = HypeMCPDocumentBackend(document: document, currentCardId: cardId)

            let getResult = await backend.callTool(
                name: "hype_get_object",
                arguments: ["object_type": .string("part"), "id_or_name": .string(part.id.uuidString)]
            )
            guard let objectValue = getResult.objectValue?["object"] else {
                Issue.record("no object payload for partType \(partType.rawValue)")
                continue
            }
            do {
                let decoded = try JSONDecoder().decode(Part.self, from: JSONEncoder().encode(objectValue))
                #expect(decoded.id == part.id, "partType \(partType.rawValue)")
                let expectedPartType = migratesTo[partType] ?? partType
                #expect(decoded.partType == expectedPartType, "partType \(partType.rawValue)")
            } catch {
                Issue.record("strict Part decode failed for partType \(partType.rawValue): \(error)")
            }
        }
    }
}

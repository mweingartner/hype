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
            // … (b) via a directly-boxed native Swift value (the transactionSummary path).
            let viaNative = HypeMCPJSONValue(any: c.native)
            #expect(viaJSON == viaNative, "typing diverged for \(c.json)")
            if c.wantBool {
                guard case .bool = viaJSON else { Issue.record(".bool expected for \(c.json)"); continue }
            } else {
                guard case .number = viaJSON else { Issue.record(".number expected for \(c.json)"); continue }
            }
        }
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
}

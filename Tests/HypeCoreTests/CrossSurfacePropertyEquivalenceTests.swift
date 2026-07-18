import Testing
import Foundation
@testable import HypeCore

// MARK: - Registry-driven property tests (Test phase, control-property-consistency)
//
// The Build-phase suites (`PartPropertyRegistryConformanceTests`,
// `PartPropertyDispatchTests`, `PartPropertyAIDispatchTests`) prove
// individual, hand-picked scenarios. This file deepens acceptance
// criterion 1 ("Property-tested across the registry, both HypeTalk and
// AI surfaces") by driving the round-trip law from `PartPropertyRegistry`
// data itself — filtered by `ValueKind`/`Mutability`, not enumerated by
// hand — so a future descriptor is exercised automatically. It then adds
// the metamorphic relation the design mock's whole premise rests on
// (§3: "one shared registry drives both") but that no existing suite
// checks directly: HypeTalk and the AI tool surface must actually AGREE
// with EACH OTHER, not just each independently match a hardcoded string.
//
// Two invariants stand in for "set the P to v; get the P returns v"
// across kinds where the exact clamp/normalization policy varies
// per-property and isn't (nor should be) tracked by this test:
//   - **boolean / color / string / json kinds**: exact literal
//     round-trip. These kinds have no clamping ambiguity — a bool is
//     "true" or "false", a color normalizes through one shared
//     validator, and plain string/JSON storage is a literal passthrough
//     (verified against the actual SET switches; the handful of
//     properties that transform their input — `script`, `musicSource`,
//     `musicInstrument`, the scene3D `object`/`modelUrl` binder pair,
//     `icon` (needs a real UUID), `name` (renames the lookup key),
//     `marked` (always errors) — are excluded by name below, each with
//     a one-line citation of the transform that makes literal equality
//     the wrong assertion for it).
//   - **number kind**: idempotence — `set(get(set(v)))` must equal
//     `get(set(v))`. This holds regardless of what a property's own
//     clamp/round/format policy is (mock §8 criterion 1's "modulo
//     documented clamping/normalization" clause, made mechanical) while
//     still catching a genuinely broken SET/GET wire-up (wrong field
//     read/written, an unstable format, a value that silently reverts).

// MARK: - Shared helpers

/// Every part type reachable from `document.parts` regardless of
/// HypeTalk-grammar addressability — the AI surface addresses parts by
/// name only, so every non-sentinel `PartType` is fair game there.
private let allRealPartTypes: [PartType] = PartType.allCases.filter { $0 != .unknown }

/// A representative, diverse spread of part types used to bound runtime
/// for descriptors with NO applicability restriction on one or both
/// verbs (`visible`, `left`, `fontColor`, …): these properties have no
/// per-type branching in their SET/GET implementation at all, so
/// testing all 26 types adds no additional signal over a good sample —
/// the interesting, bug-prone surface is the TYPE-SCOPED descriptors,
/// which always get their full applicable-type list below.
private let representativePartTypeSample: [PartType] = [
    .button, .field, .shape, .gauge, .progressView, .video, .map, .chart, .colorWell, .divider,
]

/// The full set of part types BOTH verbs of `descriptor` accept — the
/// only types where a round trip through this one descriptor is even
/// meaningful (a type outside this intersection would throw
/// `.notApplicable` on at least one verb, which is criterion 6's
/// concern, not criterion 1's).
private func applicableTypes(_ descriptor: PartPropertyRegistry.Descriptor) -> [PartType] {
    let all = Set(allRealPartTypes)
    let getTypes = descriptor.getApplicability?.types ?? all
    let setTypes = descriptor.setApplicability?.types ?? all
    return getTypes.intersection(setTypes).sorted { $0.rawValue < $1.rawValue }
}

/// `applicableTypes`, sampled down to `representativePartTypeSample`
/// when the descriptor is (effectively) universal, to keep the whole
/// suite's runtime proportionate to the number of REAL dispatch cells
/// rather than 26× every universal property.
private func typesToTest(_ descriptor: PartPropertyRegistry.Descriptor) -> [PartType] {
    let applicable = applicableTypes(descriptor)
    guard applicable.count > representativePartTypeSample.count else { return applicable }
    return representativePartTypeSample.filter { applicable.contains($0) }
}

/// Documented, by-name exceptions to "string/json kind stores its
/// input literally" — each transforms or rejects the raw value in a
/// way a generic literal-equality assertion would misreport as a bug.
private let literalRoundTripSkipNames: Set<String> = [
    "name",            // SET renames the very identifier the follow-up GET must address by; covered by its own dedicated round-trip test.
    "marked",          // H4: always errors on both GET and SET when targeting a part — never a literal round trip.
    "script",          // The AI SET wraps the raw value through `wrapScript(_:)` before storing it.
    "musicinstrument", // SET resolves through `MusicInstrumentCatalog.resolve(_:).name` — a curated catalog name, not the raw input.
    "musicsource",     // SET is a combined-source decoder (`AppleMusicItemRef.decodeSource`) with a pattern-name fallback, not a passthrough.
    "object",          // SET resolves through `Scene3DModelBindingResolver.bindModelOrObject` (asset/path lookup).
    "modelurl",        // SET resolves through `Scene3DModelBindingResolver.bindPath`, same reasoning as `object`.
    "icon",            // SET only accepts "", "0", or a real UUID string — dedicated H8 tests already cover its sentinel/clear/set behavior.
]

private func nonLegacyGetSet(kind: PartPropertyRegistry.ValueKind) -> [PartPropertyRegistry.Descriptor] {
    PartPropertyRegistry.descriptors.filter { $0.kind == kind && $0.mutability == .getSet && !$0.legacy }
}

// MARK: - AI surface: exhaustive, registry-driven round trip (criterion 1)

@Suite("Registry round trip — AI surface, driven by ValueKind (criterion 1)", .serialized)
struct AIRegistryRoundTripTests {
    private static let booleanDescriptors = nonLegacyGetSet(kind: .boolean)
    private static let colorDescriptors = nonLegacyGetSet(kind: .color)
    private static let numberDescriptors = nonLegacyGetSet(kind: .number)
    private static let stringAndJSONDescriptors = (nonLegacyGetSet(kind: .string) + nonLegacyGetSet(kind: .json))
        .filter { !literalRoundTripSkipNames.contains($0.canonical) }

    private func freshAIPart(_ type: PartType) -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let part = Part(partType: type, cardId: cardId, name: "rt", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(part)
        return (doc, cardId)
    }

    @Test("every boolean-kind descriptor round-trips true and false, on every applicable type")
    func booleanRoundTrips() async {
        #expect(!Self.booleanDescriptors.isEmpty, "no boolean-kind descriptors found — ValueKind filter is broken")
        for descriptor in Self.booleanDescriptors {
            for type in typesToTest(descriptor) {
                for boolValue in ["true", "false"] {
                    var (doc, cardId) = freshAIPart(type)
                    let executor = HypeToolExecutor()
                    let setResult = await executor.execute(
                        toolName: "set_part_property",
                        arguments: ["part_name": "rt", "property": descriptor.canonical, "value": boolValue],
                        document: &doc, currentCardId: cardId
                    )
                    guard setResult.hasPrefix("Set ") else {
                        Issue.record("\(descriptor.canonical) on \(type.rawValue): SET '\(boolValue)' unexpectedly failed: \(setResult)")
                        continue
                    }
                    let got = await executor.execute(
                        toolName: "get_part_property",
                        arguments: ["part_name": "rt", "property": descriptor.canonical],
                        document: &doc, currentCardId: cardId
                    )
                    #expect(got == boolValue, "\(descriptor.canonical) on \(type.rawValue): set '\(boolValue)', got '\(got)'")
                }
            }
        }
    }

    @Test("every color-kind descriptor normalizes to #UPPER and round-trips, on every applicable type")
    func colorRoundTrips() async {
        #expect(!Self.colorDescriptors.isEmpty, "no color-kind descriptors found — ValueKind filter is broken")
        for descriptor in Self.colorDescriptors {
            for type in typesToTest(descriptor) {
                var (doc, cardId) = freshAIPart(type)
                let executor = HypeToolExecutor()
                let setResult = await executor.execute(
                    toolName: "set_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical, "value": "#1a2b3c"],
                    document: &doc, currentCardId: cardId
                )
                guard setResult.hasPrefix("Set ") else {
                    Issue.record("\(descriptor.canonical) on \(type.rawValue): SET '#1a2b3c' unexpectedly failed: \(setResult)")
                    continue
                }
                let got = await executor.execute(
                    toolName: "get_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical],
                    document: &doc, currentCardId: cardId
                )
                #expect(got == "#1A2B3C", "\(descriptor.canonical) on \(type.rawValue): expected '#1A2B3C', got '\(got)'")
            }
        }
    }

    @Test("every non-legacy string/json-kind descriptor (minus documented transform exceptions) round-trips exactly")
    func stringAndJSONRoundTrips() async {
        #expect(!Self.stringAndJSONDescriptors.isEmpty, "no string/json-kind descriptors found — ValueKind filter is broken")
        for (i, descriptor) in Self.stringAndJSONDescriptors.enumerated() {
            for type in typesToTest(descriptor) {
                var (doc, cardId) = freshAIPart(type)
                let executor = HypeToolExecutor()
                // JSON-kind values are stored as raw, unvalidated
                // strings at this layer (verified against the actual
                // SET switches) — bracket-shaped so it's visibly
                // distinct from the plain string probe without
                // needing embedded quotes (which would only matter
                // for the HypeTalk-script variant of this test, not
                // here, but keeping one probe format for both keeps
                // this file's two suites easy to compare).
                let value = descriptor.kind == .json ? "[rtjson\(i)]" : "rtval\(i)"
                let setResult = await executor.execute(
                    toolName: "set_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical, "value": value],
                    document: &doc, currentCardId: cardId
                )
                guard setResult.hasPrefix("Set ") else {
                    Issue.record("\(descriptor.canonical) on \(type.rawValue): SET '\(value)' unexpectedly failed: \(setResult)")
                    continue
                }
                let got = await executor.execute(
                    toolName: "get_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical],
                    document: &doc, currentCardId: cardId
                )
                #expect(got == value, "\(descriptor.canonical) on \(type.rawValue): set '\(value)', got '\(got)'")
            }
        }
    }

    @Test("every number-kind descriptor stabilizes under set(get(set(v))) == get(set(v)), on every applicable type")
    func numberRoundTripsAreIdempotent() async {
        #expect(!Self.numberDescriptors.isEmpty, "no number-kind descriptors found — ValueKind filter is broken")
        for descriptor in Self.numberDescriptors {
            // `progressMin` (mock §3.1) is the one number-kind descriptor
            // whose SET is a constant/error gate rather than a plain
            // numeric store: it accepts only 0 (anything else is the
            // documented "progress always starts at 0" error). 0 is
            // itself a perfectly good idempotence probe (0 → "0" → 0 →
            // "0"), so no descriptor needs to be excluded — just probed
            // with a value its own SET actually accepts.
            let probe = descriptor.canonical == "progressmin" ? "0" : "3"
            for type in typesToTest(descriptor) {
                var (doc, cardId) = freshAIPart(type)
                let executor = HypeToolExecutor()
                let setResult = await executor.execute(
                    toolName: "set_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical, "value": probe],
                    document: &doc, currentCardId: cardId
                )
                guard setResult.hasPrefix("Set ") else {
                    Issue.record("\(descriptor.canonical) on \(type.rawValue): SET '\(probe)' unexpectedly failed: \(setResult)")
                    continue
                }
                let g1 = await executor.execute(
                    toolName: "get_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical],
                    document: &doc, currentCardId: cardId
                )
                let resetResult = await executor.execute(
                    toolName: "set_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical, "value": g1],
                    document: &doc, currentCardId: cardId
                )
                #expect(resetResult.hasPrefix("Set "), "\(descriptor.canonical) on \(type.rawValue): re-SET of its own read-back value '\(g1)' unexpectedly failed: \(resetResult)")
                let g2 = await executor.execute(
                    toolName: "get_part_property",
                    arguments: ["part_name": "rt", "property": descriptor.canonical],
                    document: &doc, currentCardId: cardId
                )
                #expect(g1 == g2, "\(descriptor.canonical) on \(type.rawValue): not idempotent — set(\(probe))→'\(g1)', set('\(g1)')→'\(g2)'")
            }
        }
    }
}

// MARK: - HypeTalk surface: registry-driven round trip, broadened from spot-checks

/// The set of part types HypeTalk's `<objectType> "<name>"` object-ref
/// grammar can actually address, reused verbatim from
/// `InterpreterFuzzTests.swift`'s property-fuzz fixture table so the
/// two files never independently drift on which types are addressable.
private let hypeTalkAddressableTypes: Set<PartType> = Set(propertyFuzzTypeSpecs.map(\.type))

/// The first applicable type for `descriptor` that HypeTalk's grammar
/// can address — `nil` when every applicable type is `.toggle`/
/// `.searchField` (the pre-existing, out-of-scope parser gap noted in
/// `InterpreterFuzzTests.swift`), in which case the descriptor is
/// skipped on this surface (still fully covered above, on the AI side).
private func firstHypeTalkAddressableType(_ descriptor: PartPropertyRegistry.Descriptor) -> PropertyFuzzTypeSpec? {
    let applicable = applicableTypes(descriptor)
    guard let type = applicable.first(where: { hypeTalkAddressableTypes.contains($0) }) else { return nil }
    return propertyFuzzTypeSpecs.first { $0.type == type }
}

@Suite("Registry round trip — HypeTalk surface, driven by ValueKind (criterion 1)", .serialized)
struct HypeTalkRegistryRoundTripTests {
    private static let booleanDescriptors = nonLegacyGetSet(kind: .boolean)
    private static let colorDescriptors = nonLegacyGetSet(kind: .color)
    private static let numberDescriptors = nonLegacyGetSet(kind: .number)
    private static let stringAndJSONDescriptors = (nonLegacyGetSet(kind: .string) + nonLegacyGetSet(kind: .json))
        .filter { !literalRoundTripSkipNames.contains($0.canonical) }

    private func freshDoc() -> (HypeDocument, UUID) {
        var doc = propertyFuzzDocument()
        let cardId = doc.cards[0].id
        let out = Part(partType: .field, cardId: cardId, name: "rtOut", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(out)
        return (doc, cardId)
    }

    private func runScript(_ script: String, doc: HypeDocument, cardId: UUID) async -> ExecutionResult {
        var doc = doc
        doc.cards[0].script = script
        return await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
    }

    @Test("every boolean-kind descriptor round-trips true and false, on its first HypeTalk-addressable applicable type")
    func booleanRoundTrips() async {
        for descriptor in Self.booleanDescriptors {
            guard let spec = firstHypeTalkAddressableType(descriptor) else { continue }
            for boolValue in ["true", "false"] {
                let (doc, cardId) = freshDoc()
                let script = """
                on openCard
                  set the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" to \(boolValue)
                  put the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" into field "rtOut"
                end openCard
                """
                let result = await runScript(script, doc: doc, cardId: cardId)
                #expect(result.status == .completed, "\(descriptor.canonical) on \(spec.objectTypeWord): \(result.error?.message ?? "")")
                let got = result.modifiedDocument?.parts.first { $0.name == "rtOut" }?.textContent
                #expect(got == boolValue, "\(descriptor.canonical) on \(spec.objectTypeWord): set '\(boolValue)', got '\(got ?? "nil")'")
            }
        }
    }

    @Test("every color-kind descriptor normalizes to #UPPER and round-trips, on its first HypeTalk-addressable applicable type")
    func colorRoundTrips() async {
        for descriptor in Self.colorDescriptors {
            guard let spec = firstHypeTalkAddressableType(descriptor) else { continue }
            let (doc, cardId) = freshDoc()
            let script = """
            on openCard
              set the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" to "#1a2b3c"
              put the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" into field "rtOut"
            end openCard
            """
            let result = await runScript(script, doc: doc, cardId: cardId)
            #expect(result.status == .completed, "\(descriptor.canonical) on \(spec.objectTypeWord): \(result.error?.message ?? "")")
            let got = result.modifiedDocument?.parts.first { $0.name == "rtOut" }?.textContent
            #expect(got == "#1A2B3C", "\(descriptor.canonical) on \(spec.objectTypeWord): expected '#1A2B3C', got '\(got ?? "nil")'")
        }
    }

    @Test("every non-legacy string/json-kind descriptor (minus documented transform exceptions) round-trips exactly")
    func stringAndJSONRoundTrips() async {
        for (i, descriptor) in Self.stringAndJSONDescriptors.enumerated() {
            guard let spec = firstHypeTalkAddressableType(descriptor) else { continue }
            // Bracket-shaped, quote-free probe: this variant is embedded
            // literally inside a HypeTalk quoted-string literal, so it
            // must not itself contain a `"` (which would end the
            // literal early in the lexer).
            let value = descriptor.kind == .json ? "[rtjson\(i)]" : "rtval\(i)"
            let (doc, cardId) = freshDoc()
            let script = """
            on openCard
              set the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" to "\(value)"
              put the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" into field "rtOut"
            end openCard
            """
            let result = await runScript(script, doc: doc, cardId: cardId)
            #expect(result.status == .completed, "\(descriptor.canonical) on \(spec.objectTypeWord): \(result.error?.message ?? "")")
            let got = result.modifiedDocument?.parts.first { $0.name == "rtOut" }?.textContent
            #expect(got == value, "\(descriptor.canonical) on \(spec.objectTypeWord): set '\(value)', got '\(got ?? "nil")'")
        }
    }

    @Test("every number-kind descriptor stabilizes under set(get(set(v))) == get(set(v))")
    func numberRoundTripsAreIdempotent() async {
        for descriptor in Self.numberDescriptors {
            guard let spec = firstHypeTalkAddressableType(descriptor) else { continue }
            let probe = descriptor.canonical == "progressmin" ? "0" : "3"
            let (doc, cardId) = freshDoc()
            let firstScript = """
            on openCard
              set the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" to \(probe)
              put the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" into field "rtOut"
            end openCard
            """
            let firstResult = await runScript(firstScript, doc: doc, cardId: cardId)
            #expect(firstResult.status == .completed, "\(descriptor.canonical) on \(spec.objectTypeWord): \(firstResult.error?.message ?? "")")
            guard let afterFirstDoc = firstResult.modifiedDocument else { continue }
            let g1 = afterFirstDoc.parts.first { $0.name == "rtOut" }?.textContent ?? ""

            let secondScript = """
            on openCard
              set the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" to "\(g1)"
              put the \(descriptor.canonical) of \(spec.objectTypeWord) "\(spec.partName)" into field "rtOut"
            end openCard
            """
            let secondResult = await runScript(secondScript, doc: afterFirstDoc, cardId: cardId)
            #expect(secondResult.status == .completed, "\(descriptor.canonical) on \(spec.objectTypeWord): re-SET of read-back '\(g1)' unexpectedly failed: \(secondResult.error?.message ?? "")")
            let g2 = secondResult.modifiedDocument?.parts.first { $0.name == "rtOut" }?.textContent ?? ""
            #expect(g1 == g2, "\(descriptor.canonical) on \(spec.objectTypeWord): not idempotent — set(\(probe))→'\(g1)', set('\(g1)')→'\(g2)'")
        }
    }
}

// MARK: - Cross-surface metamorphic equivalence (design mock §3: "one shared registry drives both")
//
// The two suites above prove each surface round-trips against ITSELF.
// This suite is the actual cross-surface invariant the whole change
// exists to deliver: write through one surface, read through the
// OTHER, and the two must agree — not "both independently match a
// hardcoded literal" (which is all the Build-phase suites checked) but
// "surface A's write is visible, in the same terms, through surface
// B's read." Numeric kinds compare by parsed value (Double), since the
// two surfaces have an intentionally different — but already
// documented and tested elsewhere — numeric GET format (HypeTalk's
// trailing-zero-trimmed `formatNumber` vs the AI surface's plain
// `String(Double)`, e.g. "5" vs "5.0"); every other kind compares by
// exact string equality, since neither surface applies kind-specific
// reformatting to strings/bools/colors.

@Suite("Cross-surface equivalence — HypeTalk SET / AI GET and vice versa")
struct CrossSurfaceValueEquivalenceTests {
    private func hypeTalkSet(_ script: String, doc: HypeDocument, cardId: UUID) async -> HypeDocument? {
        var doc = doc
        doc.cards[0].script = script
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        return result.modifiedDocument
    }

    /// One representative descriptor per `ValueKind`, each on a
    /// distinct part type, so the sample spans every kind's comparison
    /// rule without re-running the full exhaustive sweep above twice.
    private struct Sample: Sendable {
        let descriptor: String
        let type: PartType
        let objectTypeWord: String
        // Already in each kind's OWN normalized storage form (color is
        // pre-uppercased) — the two surfaces must agree on the exact
        // value actually stored, not on an arbitrary pre-normalization
        // input; the string/color/boolean/json round-trip suites above
        // already prove the normalization step itself is correct.
        let value: String
        let kind: PartPropertyRegistry.ValueKind
    }

    private static let samples: [Sample] = [
        Sample(descriptor: "visible", type: .field, objectTypeWord: "field", value: "false", kind: .boolean),
        Sample(descriptor: "fillcolor", type: .shape, objectTypeWord: "shape", value: "#1A2B3C", kind: .color),
        Sample(descriptor: "gaugemin", type: .gauge, objectTypeWord: "gauge", value: "7", kind: .number),
        Sample(descriptor: "url", type: .webpage, objectTypeWord: "webpage", value: "crossSurfaceProbe", kind: .string),
        Sample(descriptor: "chartdata", type: .chart, objectTypeWord: "chart", value: "[crossSurfaceJSON]", kind: .json),
    ]

    private func numericValuesAgree(_ a: String, _ b: String) -> Bool {
        guard let da = Double(a), let db = Double(b) else { return a == b }
        return abs(da - db) < 1e-9
    }

    private func valuesAgree(_ a: String, _ b: String, kind: PartPropertyRegistry.ValueKind) -> Bool {
        kind == .number ? numericValuesAgree(a, b) : a == b
    }

    @Test("SET via HypeTalk, GET via the AI tool surface: same value, every ValueKind", arguments: CrossSurfaceValueEquivalenceTests.samples)
    private func hypeTalkSetAIGet(sample: Sample) async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var part = Part(partType: sample.type, cardId: cardId, name: "x", left: 0, top: 0, width: 100, height: 40)
        if sample.type == .chart { part.chartData = ChartConfig().toJSON() }
        doc.addPart(part)
        let script = """
        on openCard
          set the \(sample.descriptor) of \(sample.objectTypeWord) "x" to \(sample.kind == .number ? sample.value : "\"\(sample.value)\"")
        end openCard
        """
        guard let afterSet = await hypeTalkSet(script, doc: doc, cardId: cardId) else {
            Issue.record("\(sample.descriptor): HypeTalk SET failed to produce a modified document")
            return
        }
        var aiDoc = afterSet
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "x", "property": sample.descriptor],
            document: &aiDoc, currentCardId: cardId
        )
        #expect(valuesAgree(got, sample.value, kind: sample.kind), "\(sample.descriptor): HypeTalk set '\(sample.value)', AI got '\(got)'")
    }

    @Test("SET via the AI tool surface, GET via HypeTalk: same value, every ValueKind", arguments: CrossSurfaceValueEquivalenceTests.samples)
    private func aiSetHypeTalkGet(sample: Sample) async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var part = Part(partType: sample.type, cardId: cardId, name: "x", left: 0, top: 0, width: 100, height: 40)
        if sample.type == .chart { part.chartData = ChartConfig().toJSON() }
        doc.addPart(part)
        let setResult = await HypeToolExecutor().execute(
            toolName: "set_part_property",
            arguments: ["part_name": "x", "property": sample.descriptor, "value": sample.value],
            document: &doc, currentCardId: cardId
        )
        #expect(setResult.hasPrefix("Set "), "\(sample.descriptor): AI SET unexpectedly failed: \(setResult)")
        var doc2 = doc
        doc2.cards[0].script = """
        on openCard
          put the \(sample.descriptor) of \(sample.objectTypeWord) "x" into field "out"
        end openCard
        """
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 60, width: 100, height: 40)
        doc2.addPart(out)
        let result = await runOnLargeStack { [doc2, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc2, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "\(sample.descriptor): \(result.error?.message ?? "")")
        let got = result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent ?? ""
        #expect(valuesAgree(got, sample.value, kind: sample.kind), "\(sample.descriptor): AI set '\(sample.value)', HypeTalk got '\(got)'")
    }
}

// MARK: - Cross-surface byte-identical error copy (Condition 11)
//
// Both surfaces construct their error strings from the SAME
// `PartPropertyRegistry` message functions, so this should hold by
// construction — but "should, by construction" is exactly the claim a
// test should verify mechanically rather than trust. Driven from the
// registry itself (every read-only descriptor, every type-scoped
// descriptor) rather than a hand-picked handful, so a new descriptor is
// covered automatically.

@Suite("Cross-surface error copy — byte-identical on both surfaces")
struct CrossSurfaceErrorCopyTests {
    private func hypeTalkSetError(_ property: String, type: PartType, objectTypeWord: String, partName: String, value: String) async -> String? {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let part = Part(partType: type, cardId: cardId, name: partName, left: 0, top: 0, width: 100, height: 40)
        doc.addPart(part)
        doc.cards[0].script = """
        on openCard
          set the \(property) of \(objectTypeWord) "\(partName)" to "\(value)"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        return result.error?.message
    }

    private func aiSetError(_ property: String, type: PartType, partName: String, value: String) async -> String {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let part = Part(partType: type, cardId: cardId, name: partName, left: 0, top: 0, width: 100, height: 40)
        doc.addPart(part)
        return await HypeToolExecutor().execute(
            toolName: "set_part_property",
            arguments: ["part_name": partName, "property": property, "value": value],
            document: &doc, currentCardId: cardId
        )
    }

    @Test("read-only descriptors: SET error is byte-identical on both surfaces, for every read-only descriptor")
    func readOnlyErrorsMatch() async {
        let readOnly = PartPropertyRegistry.descriptors.filter { $0.mutability == .readOnly && !$0.legacy }
        #expect(!readOnly.isEmpty)
        for descriptor in readOnly {
            // resolveSet short-circuits to `.readOnly` regardless of
            // applicability/part type (proven registry-wide by
            // `PartPropertyRegistryConformanceTests.readOnlyAlwaysReadOnly`),
            // so any type is a valid probe here.
            let hypeTalkError = await hypeTalkSetError(descriptor.canonical, type: .button, objectTypeWord: "button", partName: "ro", value: "x")
            let aiError = await aiSetError(descriptor.canonical, type: .button, partName: "ro", value: "x")
            #expect(hypeTalkError == aiError, "\(descriptor.canonical): HypeTalk='\(hypeTalkError ?? "nil")' AI='\(aiError)'")
            #expect(hypeTalkError?.contains(descriptor.canonical) == true, "\(descriptor.canonical): HypeTalk error missing the property name: \(hypeTalkError ?? "nil")")
        }
    }

    @Test("type-scoped descriptors: SET error is byte-identical on both surfaces for a definitely-wrong type")
    func wrongTypeErrorsMatch() async {
        let scoped = PartPropertyRegistry.descriptors.filter { $0.setApplicability != nil && $0.mutability == .getSet && !$0.legacy }
        #expect(!scoped.isEmpty)
        for descriptor in scoped {
            guard let applicability = descriptor.setApplicability,
                  let wrongType = allRealPartTypes.first(where: { !applicability.types.contains($0) }),
                  // Only a HypeTalk-addressable wrong type lets us build
                  // a `set the X of <type> "name" to ...` script at all;
                  // the AI half of the comparison still runs for every
                  // scoped descriptor regardless (addressed by name).
                  let objectWord = propertyFuzzTypeSpecs.first(where: { $0.type == wrongType })?.objectTypeWord
            else { continue }
            let aiError = await aiSetError(descriptor.canonical, type: wrongType, partName: "wt", value: "x")
            #expect(aiError.contains("does not apply"), "\(descriptor.canonical) on \(wrongType.rawValue): unexpected AI error shape: \(aiError)")
            let hypeTalkError = await hypeTalkSetError(descriptor.canonical, type: wrongType, objectTypeWord: objectWord, partName: "wt", value: "x")
            #expect(hypeTalkError == aiError, "\(descriptor.canonical) on \(wrongType.rawValue): HypeTalk='\(hypeTalkError ?? "nil")' AI='\(aiError)'")
        }
    }

    @Test("garbage color: SET error is byte-identical on both surfaces, for every color-kind descriptor")
    func garbageColorErrorsMatch() async {
        let colorDescriptors = PartPropertyRegistry.descriptors.filter { $0.kind == .color && $0.mutability == .getSet && !$0.legacy }
        #expect(!colorDescriptors.isEmpty)
        for descriptor in colorDescriptors {
            guard let spec = firstHypeTalkAddressableType(descriptor) else { continue }
            let hypeTalkError = await hypeTalkSetError(descriptor.canonical, type: spec.type, objectTypeWord: spec.objectTypeWord, partName: spec.partName, value: "reddish")
            let aiError = await aiSetError(descriptor.canonical, type: spec.type, partName: spec.partName, value: "reddish")
            #expect(hypeTalkError == aiError, "\(descriptor.canonical): HypeTalk='\(hypeTalkError ?? "nil")' AI='\(aiError)'")
            #expect(aiError.contains("is not a color"), "\(descriptor.canonical): unexpected error shape: \(aiError)")
        }
    }

    @Test("unknown-property typo: SET error is byte-identical on both surfaces")
    func unknownPropertyErrorsMatch() async {
        for typo in ["gaugvalue", "totallyBogusProperty", "fillcolour"] {
            let hypeTalkError = await hypeTalkSetError(typo, type: .gauge, objectTypeWord: "gauge", partName: "g", value: "x")
            let aiError = await aiSetError(typo, type: .gauge, partName: "g", value: "x")
            #expect(hypeTalkError == aiError, "'\(typo)': HypeTalk='\(hypeTalkError ?? "nil")' AI='\(aiError)'")
        }
    }

    @Test("`marked` targeting a part: SET error is byte-identical on both surfaces")
    func markedErrorsMatch() async {
        let hypeTalkError = await hypeTalkSetError("marked", type: .button, objectTypeWord: "button", partName: "b", value: "true")
        let aiError = await aiSetError("marked", type: .button, partName: "b", value: "true")
        #expect(hypeTalkError == aiError)
        #expect(aiError == "\"marked\" is a card property — try the marked of this card.")
    }
}

// MARK: - Regression: AI-surface part-property gaps found by this Test phase
//
// The exhaustive registry-driven suites above, plus
// `PartPropertyRegistryConformanceTests.swift`'s strengthened
// `noPlaceholderValues` test, together caught FIFTEEN registry
// descriptors that `HypeToolExecutor`'s `get_part_property`/
// `set_part_property` switches had never implemented at all — despite
// the registry declaring them ordinary get(+set) properties HypeTalk
// already fully supports — so the tools silently answered "Unknown
// property" (SET) or fell through to a placeholder (GET) instead of
// dispatching:
//   - `right`, `bottom`, `centered`, `textHeight`, `lineSize` (universal
//     number/boolean kinds, caught automatically by
//     `AIRegistryRoundTripTests` above — SET was missing; GET already
//     existed for the first four).
//   - The spriteArea display flags `showsPhysics`/`showsFPS`/
//     `showsNodeCount`/`scaleMode` (GET+SET both missing).
//   - `shapeType`, `animating`, `sceneName`, `sceneCount` (GET missing;
//     these are read-only or boolean/enumeration kinds
//     `noPlaceholderValues` caught since the exhaustive suites
//     deliberately don't probe `.enumeration` kind, and `animating`/
//     `sceneName`/`sceneCount` are `.readOnly` so the round-trip
//     suites — which only cover `.getSet` — never touched them).
//   - `longName`, `owner`, `number`/`partNumber` — also caught by
//     `noPlaceholderValues`, but these three genuinely need
//     `document`/`currentCardId` (a card/background name lookup, or
//     the CURRENT card's full part list) that `partPropertyReadValue`'s
//     bare-`Part` signature can't provide, so they're fixed as
//     intercepts at the `get_part_property` call site instead (see
//     `HypeToolExecutor.swift`) and remain a documented, intentional
//     placeholder in `list_all_properties` specifically (which only
//     has a `Part`) — the same category as the pre-existing `marked`
//     exception.
// Every case fixed in `HypeToolExecutor.swift` by mirroring the
// existing HypeTalk `Interpreter.swift` behavior exactly.

@Suite("Regression — AI surface sprite-area display-flag properties (Test-phase fix)")
struct SpriteAreaDisplayFlagAIRegressionTests {
    private func freshSpriteArea() -> (HypeDocument, UUID) {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let area = Part(partType: .spriteArea, cardId: cardId, name: "area", left: 0, top: 0, width: 300, height: 200)
        doc.addPart(area)
        return (doc, cardId)
    }

    @Test("scaleMode round-trips through set_part_property/get_part_property on a sprite area")
    func scaleModeRoundTrips() async {
        var (doc, cardId) = freshSpriteArea()
        let executor = HypeToolExecutor()
        let setResult = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "area", "property": "scalemode", "value": "aspectFit"],
            document: &doc, currentCardId: cardId
        )
        #expect(setResult.hasPrefix("Set "), "unexpected: \(setResult)")
        let got = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "area", "property": "scalemode"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "aspectFit", "expected 'aspectFit', got '\(got)'")
    }

    @Test("scaleMode SET silently no-ops on an unrecognized value, matching HypeTalk exactly")
    func scaleModeInvalidValueNoOps() async {
        var (doc, cardId) = freshSpriteArea()
        let executor = HypeToolExecutor()
        _ = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "area", "property": "scalemode", "value": "fill"],
            document: &doc, currentCardId: cardId
        )
        let setResult = await executor.execute(
            toolName: "set_part_property",
            arguments: ["part_name": "area", "property": "scalemode", "value": "not-a-real-mode"],
            document: &doc, currentCardId: cardId
        )
        #expect(setResult.hasPrefix("Set "), "unexpected: \(setResult)")
        let got = await executor.execute(
            toolName: "get_part_property",
            arguments: ["part_name": "area", "property": "scalemode"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "fill", "an invalid scaleMode must leave the prior value untouched, got '\(got)'")
    }

    @Test("scaleMode set via the AI surface is visible through HypeTalk's GET (cross-surface parity)")
    func scaleModeCrossSurfaceParity() async {
        var (doc, cardId) = freshSpriteArea()
        let setResult = await HypeToolExecutor().execute(
            toolName: "set_part_property",
            arguments: ["part_name": "area", "property": "scalemode", "value": "resizeFill"],
            document: &doc, currentCardId: cardId
        )
        #expect(setResult.hasPrefix("Set "), "unexpected: \(setResult)")
        let out = Part(partType: .field, cardId: cardId, name: "out", left: 0, top: 220, width: 100, height: 40)
        doc.addPart(out)
        doc.cards[0].script = """
        on openCard
          put the scalemode of spritearea "area" into field "out"
        end openCard
        """
        let result = await runOnLargeStack { [doc, cardId] in MessageDispatcher().dispatch(
            message: "openCard", params: [], targetId: cardId,
            document: doc, currentCardId: cardId
        ) }
        #expect(result.status == .completed, "\(result.error?.message ?? "")")
        let got = result.modifiedDocument?.parts.first { $0.name == "out" }?.textContent
        #expect(got == "resizeFill", "expected 'resizeFill', got '\(got ?? "nil")'")
    }
}

@Suite("Regression — AI surface read-only/context-dependent property gaps (Test-phase fix)")
struct ReadOnlyAndContextDependentAIRegressionTests {
    @Test("shapeType GET returns the shape's own type (distinct from the polymorphic `style` bare word)")
    func shapeTypeReturnsRealValue() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var shape = Part(partType: .shape, cardId: cardId, name: "s", left: 0, top: 0, width: 100, height: 40)
        shape.shapeType = .oval
        doc.addPart(shape)
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "s", "property": "shapetype"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "oval", "expected 'oval', got '\(got)'")
    }

    @Test("animating GET returns false on a part with no active animation (never the placeholder/unknown fallback)")
    func animatingReturnsRealValue() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let image = Part(partType: .image, cardId: cardId, name: "i", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(image)
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "i", "property": "animating"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "false", "expected 'false', got '\(got)'")
    }

    @Test("sceneName/sceneCount read directly from the part's own SpriteAreaSpec")
    func sceneNameAndCountReturnRealValues() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        var area = Part(partType: .spriteArea, cardId: cardId, name: "area", left: 0, top: 0, width: 300, height: 200)
        area.updateSpriteAreaSpec { spec in
            spec.addScene(named: "Level 2")
        }
        doc.addPart(area)
        let name = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "area", "property": "scenename"],
            document: &doc, currentCardId: cardId
        )
        let count = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "area", "property": "scenecount"],
            document: &doc, currentCardId: cardId
        )
        #expect(!name.isEmpty && name != "Unknown property 'scenename'", "unexpected sceneName: '\(name)'")
        #expect(count == "2", "expected 2 scenes (default + added), got '\(count)'")
    }

    @Test("longName returns the card path, matching HypeTalk's own descriptor shape")
    func longNameReturnsCardPath() async {
        var doc = HypeDocument.newDocument(name: "Test")
        let cardId = doc.cards[0].id
        let button = Part(partType: .button, cardId: cardId, name: "OK", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(button)
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "OK", "property": "longname"],
            document: &doc, currentCardId: cardId
        )
        #expect(got.contains("button \"OK\""), "expected the button descriptor in the long name, got '\(got)'")
        #expect(got.contains("Card 1"), "expected the owning card's name in the long name, got '\(got)'")
    }

    @Test("owner returns the owning card's descriptor")
    func ownerReturnsCardDescriptor() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let field = Part(partType: .field, cardId: cardId, name: "f", left: 0, top: 0, width: 100, height: 40)
        doc.addPart(field)
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "f", "property": "owner"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "card \"Card 1\"", "expected 'card \"Card 1\"', got '\(got)'")
    }

    @Test("number/partNumber returns the 1-based position among the current card's parts")
    func numberReturnsOrdinalPosition() async {
        var doc = HypeDocument.newDocument()
        let cardId = doc.cards[0].id
        let first = Part(partType: .button, cardId: cardId, name: "first", left: 0, top: 0, width: 100, height: 40)
        let second = Part(partType: .button, cardId: cardId, name: "second", left: 0, top: 60, width: 100, height: 40)
        doc.addPart(first)
        doc.addPart(second)
        let got = await HypeToolExecutor().execute(
            toolName: "get_part_property",
            arguments: ["part_name": "second", "property": "number"],
            document: &doc, currentCardId: cardId
        )
        #expect(got == "2", "expected '2' (second part on the card), got '\(got)'")
    }
}

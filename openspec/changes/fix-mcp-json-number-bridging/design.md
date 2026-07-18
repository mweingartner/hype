# Design: Fix MCP JSON number/boolean bridging

## Context

`hype_get_object` / `hype_get_stack_document` serialize a `Part`/`HypeDocument` by encoding it to JSON, re-parsing with `JSONSerialization.jsonObject` (→ `Any` tree of `NSNumber`/`NSString`/…), and wrapping that in `HypeMCPJSONValue` via `init(any:)`. `JSONSerialization` represents both JSON numbers and JSON booleans as `NSNumber`; a boolean is a tagged `CFBoolean`, a number is a plain `NSNumber`. Swift bridges `NSNumber(0)`/`NSNumber(1)` to `Bool` (`as? Bool` succeeds), so the current `case let value as Bool` — placed *before* the numeric cases — captures numeric `0`/`1` as `.bool`. The result is emitted to the client, whose strict `JSONDecoder().decode(Part.self, …)` then throws on the many `Part` numeric fields defaulting to `0`/`1`.

The Codable `init(from:)` path (line 11) is NOT affected: `JSONDecoder` keeps JSON booleans and numbers as distinct types, so `try? container.decode(Bool.self)` on a JSON number fails and falls through to the numeric decode. The encode path (`encode(to:)`, line 30) is NOT affected: `.number(Double)` encodes whole doubles as JSON integers (`1.0` → `1`), which strict `Int`/`Double` decoders accept. **The bug is isolated to `init(any:)`.**

## Goals / Non-Goals

- Goal: `init(any:)` types a JSON boolean as `.bool` and a numeric `0`/`1` (and every other number) as `.number`, so `get_object` output round-trips through a strict `Part` decode.
- Non-Goal: no change to the wire format for correct values, the enum shape, `init(from:)`, `encode(to:)`, the masking transform, or any tool behavior. No new `.int` case (numbers stay `.number(Double)` — the existing contract).

## Decisions

**Disambiguate `NSNumber` via `CFBoolean` identity.** Add a single `case let value as NSNumber` ahead of the `Bool`/`Int`/`Double`/`Float` cases:

```swift
case let value as NSNumber:
    // JSONSerialization returns NSNumber for BOTH JSON numbers and JSON
    // booleans; NSNumber(0)/(1) also satisfy `as? Bool`. A real JSON boolean
    // is a CFBoolean — distinguish by type id so numeric 0/1 stays a number.
    if CFGetTypeID(value) == CFBooleanGetTypeID() {
        self = .bool(value.boolValue)
    } else {
        self = .number(value.doubleValue)
    }
```

The subsequent `Bool`/`Int`/`Double`/`Float` cases become unreachable for any `NSNumber`-bridged input (all numbers and bools bridge to `NSNumber`, including native Swift `Bool`/`Int`/`Double` passed as `Any`), so they are removed. `String`, `HypeMCPJSONValue`, `[Any]`, `[String: Any]`, and the `.null` default are unchanged and ordered so `String` (which does not bridge to `NSNumber`) is matched first.

Alternative rejected: merely reordering (numeric cases before `Bool`) — a native Swift `Bool` passed as `Any` would then be mis-typed as `.number(1)`; the `CFBoolean` check is the correct, symmetric disambiguation for both directions.

## Risks / Trade-offs

- [A value that was *intended* as a boolean but stored numerically somewhere upstream now serializes as a number] → No such path: `Part`'s boolean fields are Swift `Bool`, which JSONEncoder emits as JSON `true`/`false` → `CFBoolean` → still `.bool`. Only genuine JSON numbers change type, and correctly.
- [Foundation import] → `CFGetTypeID`/`CFBooleanGetTypeID`/`NSNumber` require `Foundation`, already imported by this file.

## Conditions for Builder

1. Change ONLY `init(any:)` in `Sources/HypeCore/MCP/HypeMCPTypes.swift`; do not touch `init(from:)`, `encode(to:)`, the enum cases, or any masking/tool code.
2. A genuine JSON boolean (`true`/`false`) MUST remain `.bool`; every JSON number (including `0` and `1`) MUST become `.number`. Verify both directions with a property test over the codec.
3. The real-Part round-trip MUST hold: a `Part` with numeric fields at `0`/`1` (e.g. `rotation=0`, `family=1`, `strokeWidth=1`), serialized via `hype_get_object`, MUST strict-`JSONDecoder().decode(Part.self, …)` cleanly.
4. Remove the test-scoped `avoidingKnownZeroOrOneNumericBridgingDefaults` workaround from `MCPMaskingTests.swift` and confirm those tests pass WITHOUT it (its removal is proof the real bug is fixed). The MCP masking behavior and its suites MUST stay green.
5. Codec change → include a seeded, reproducible fuzz/property pass over `Any` inputs (bool, ints incl. 0/1/-1/large, doubles, strings, nested arrays/objects) asserting correct `.bool`/`.number`/`.string`/`.array`/`.object` typing and round-trip stability. **The pass MUST construct each `Any` two ways and assert identical typing for both (Security-plan advisory): (a) via `JSONSerialization.jsonObject` on encoded JSON, and (b) by boxing native Swift `Bool`/`Int`/`Double`/`Float` literals directly as `Any` — this exercises the real native-`Any` call sites (`transactionSummary`, `debugPartSummary`) whose `Bool` values never touch `JSONSerialization`.**

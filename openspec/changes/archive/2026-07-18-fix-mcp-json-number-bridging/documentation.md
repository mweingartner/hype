# MCP JSON number/boolean bridging fix

## Purpose

Corrects a type-bridging defect in `HypeMCPJSONValue.init(any:)`: `JSONSerialization` represents both JSON numbers and JSON booleans as `NSNumber`, and `NSNumber(0)`/`NSNumber(1)` satisfy Swift's `as? Bool` cast — so with the `Bool` case checked before the numeric cases, any Part numeric field valued exactly `0` or `1` (the default for `rotation`, `family`, `strokeWidth`, `gaugeMax`, `progressTotal`, `controlValue`, …) was silently emitted as a JSON boolean by `hype_get_object` / `hype_get_stack_document`.

## Value

The GET→edit→REPLACE round-trip the MCP object tools exist to support now works for the large fraction of real parts that hold `0`/`1` numeric defaults: a strict `JSONDecoder().decode(Part.self, …)` of the tool output no longer throws `DecodingError.typeMismatch` ("Expected Double but found bool"). A latent correctness bug is also closed as a side effect — the previous explicit `Bool`/`Int`/`Double`/`Float` cases dropped other numeric types (`Int8/64`, `UInt`, `CGFloat` boxed as `Any`) to `.null`; the single `NSNumber` case now types every numeric correctly.

## Scope

- **In scope**: the `Any`→`HypeMCPJSONValue` bridge (`init(any:)`) only. A genuine JSON boolean (a `CFBoolean`, identified by `CFGetTypeID(value) == CFBooleanGetTypeID()`) types as `.bool`; every other `NSNumber` types as `.number`. This is symmetric for native Swift `Bool`/`Int`/`Double` boxed directly as `Any` (e.g. the `debugPartSummary` call site, `HypeDebugServer.swift:1579`, which builds a `[String: Any]` of native values and wraps it via `HypeMCPJSONValue(any:)`), because a Swift `Bool` bridges to the same `kCFBoolean` singleton.
- **Not touched**: the Codable `init(from:)` and `encode(to:)` paths (already correct — `JSONDecoder` distinguishes bool from number, and whole doubles encode as JSON integers), the `HypeMCPJSONValue` enum shape (numbers remain `.number(Double)` — no new `.int` case), and the secure-field masking layer (which runs on the `Part` struct before this codec and only touches String fields — orthogonal).

## Functional details

`init(any:)` matches, in order: an existing `HypeMCPJSONValue` (passthrough), `String`, then a single `NSNumber` case — `CFBoolean` → `.bool(value.boolValue)`, else `.number(value.doubleValue)` — then `[Any]`/`[String: Any]` (recursive), else `.null`. The old order-dependent `Bool`/`Int`/`Double`/`Float` cases are removed; all numeric and boolean inputs (whether NSNumber from `JSONSerialization` or native Swift values boxed as `Any`) flow through the one `NSNumber` case.

## Usage

Author-facing behavior is unchanged; this is an internal codec correction. The observable contract:

- **A number stays a number.** `HypeMCPJSONValue(any:)` of the `JSONSerialization` output for `{"a": 0, "b": 1, "c": 42}` yields `.number` for `a`, `b`, and `c` (previously `a`/`b` were `.bool`).
- **A boolean stays a boolean.** The same for `{"t": true, "f": false}` yields `.bool(true)` / `.bool(false)`.
- **A default-valued part round-trips.** A `Part` with `rotation == 0`, `family == 1`, `strokeWidth == 1`, read via `hype_get_object` and re-encoded, decodes cleanly with a strict `JSONDecoder().decode(Part.self, …)` — the scenario that previously threw.

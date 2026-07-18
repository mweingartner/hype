# Fix MCP JSON number/boolean bridging

## Why

`HypeMCPJSONValue.init(any:)` (`Sources/HypeCore/MCP/HypeMCPTypes.swift:329`) checks `case let value as Bool` before the numeric cases. `JSONSerialization` returns `NSNumber` for JSON numbers, and `NSNumber(0)`/`NSNumber(1)` satisfy Swift's `as? Bool` cast, so any Part numeric property whose value is exactly `0` or `1` (the default for many — `rotation`, `family`, `strokeWidth`, `gaugeMax`, `progressTotal`, `controlValue`) is silently re-typed as a JSON boolean in `hype_get_object` / `hype_get_stack_document` output. A strict `JSONDecoder().decode(Part.self, …)` of that response then throws a type mismatch — breaking the GET→edit→REPLACE round-trip the MCP object tools exist to support, for a large fraction of real parts, regardless of `fieldStyle`. Found by the `mask-mcp-object-tools` Builder, which worked around it in tests only.

## What Changes

- Disambiguate `NSNumber` before the `Bool` cast in `init(any:)`: a genuine JSON boolean (a `CFBoolean`, `CFGetTypeID == CFBooleanGetTypeID()`) becomes `.bool`; any other `NSNumber` (including numeric `0`/`1`) becomes `.number`.
- Regression + property/fuzz tests over the `Any`→`HypeMCPJSONValue` codec and a real `Part` round-trip (`get_object` JSON → strict `Part` decode).
- Remove the now-unnecessary test-scoped workaround `avoidingKnownZeroOrOneNumericBridgingDefaults` in `MCPMaskingTests.swift`.

## Capabilities

### New Capabilities

- `mcp-json-codec` — the `Any`↔`HypeMCPJSONValue` bridging contract.

### Modified Capabilities

## Impact

`Sources/HypeCore/MCP/HypeMCPTypes.swift` (the `init(any:)` bridge); the `hype_get_object`/`hype_get_stack_document`/`hype_replace_part` round-trip they feed. No wire-format change to correct clients; corrects the type of `0`/`1` numbers only. Codec change → property/fuzz tests required.

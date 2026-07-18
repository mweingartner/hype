# Mcp Json Codec

## Requirements

### Requirement: Any→HypeMCPJSONValue preserves JSON number vs boolean typing

`HypeMCPJSONValue.init(any:)` SHALL type a value produced by `JSONSerialization` (an `NSNumber` tree) so that a genuine JSON boolean becomes `.bool` and every JSON number — including the integer values `0` and `1` — becomes `.number`. Disambiguation SHALL use `CFBoolean` identity (`CFGetTypeID(value) == CFBooleanGetTypeID()`), not Swift's `as? Bool` bridging (which `NSNumber(0)`/`NSNumber(1)` satisfy).

#### Scenario: numeric 0 and 1 stay numbers

- **WHEN** `init(any:)` receives the `JSONSerialization` output for `{"a": 0, "b": 1, "c": 42}`
- **THEN** `a`, `b`, and `c` are each `.number` (not `.bool`)

#### Scenario: JSON booleans stay booleans

- **WHEN** `init(any:)` receives the `JSONSerialization` output for `{"t": true, "f": false}`
- **THEN** `t` is `.bool(true)` and `f` is `.bool(false)`

### Requirement: MCP object reads round-trip through a strict Part decode

A `Part` serialized by `hype_get_object` (or `hype_get_stack_document`) SHALL decode cleanly via a strict `JSONDecoder().decode(Part.self, from:)`, including parts whose numeric fields hold the default values `0` or `1`.

#### Scenario: a default-valued part round-trips

- **WHEN** a `Part` with `rotation == 0`, `family == 1`, and `strokeWidth == 1` is read via `hype_get_object` and the returned JSON is decoded with a strict `JSONDecoder`
- **THEN** the decode succeeds and the decoded part's numeric fields equal the originals

# Tasks — fix-mcp-json-number-bridging

## 1. Fix + tests

- [x] 1.1 In `Sources/HypeCore/MCP/HypeMCPTypes.swift` `init(any:)`, add a `case let value as NSNumber` (before Bool/Int/Double/Float) that maps `CFGetTypeID == CFBooleanGetTypeID()` → `.bool(value.boolValue)`, else `.number(value.doubleValue)`; remove the now-unreachable Bool/Int/Double/Float cases. Touch nothing else in the file.
- [x] 1.2 New `Tests/HypeCoreTests/MCPJSONCodecTests.swift`: unit tests (numeric 0/1 → .number; true/false → .bool; nested), a seeded property/fuzz pass over Any inputs, and the real-Part round-trip (`hype_get_object` JSON → strict `JSONDecoder().decode(Part.self)` with rotation=0/family=1/strokeWidth=1).
- [x] 1.3 Remove `avoidingKnownZeroOrOneNumericBridgingDefaults` and its call sites from `Tests/HypeCoreTests/MCPMaskingTests.swift`; confirm those tests pass without it.
- [x] 1.4 Full filtered suite green (real count); MCP masking + Part round-trip suites green.

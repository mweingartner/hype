# Tasks

- [x] 1. `HypeMCPDocumentBackend.swift`: add private `secureFieldMask` constant and the two private `maskedForTransport` helpers (Part + HypeDocument) per design.md Decision 1.
- [x] 2. Wrap the five part-bearing serialization sites: L109 (`/part/{id}/full`), L489 (`fullDocumentResource`), L515 (`getObject` part), L570 (`setScript` part echo), replacePart echo.
- [x] 3. `replacePart` sentinel-preserve guard + `preservedSecureText` response key + result-string note per design.md Decision 2.
- [x] 4. Description updates: three tools in `HypeMCPToolBridge.swift` (L95, L100, L172) + `/document` resource description (`HypeMCPDocumentBackend.swift` L68), exact strings from design.md Decision 4.
- [x] 5. New `Tests/HypeCoreTests/MCPMaskingTests.swift`: tests 1-11 plus the seeded leak sweep and no-op round-trip from the testing notes.
- [x] 6. Full HypeCoreTests run with real non-zero count; `SecurityRegressionTests`, `ScriptStorageGateIntegrationTests`, `HypeMCPTests` green and unmodified.

# Mask MCP Object Tools

## Why

The Security (plan) review of `control-property-consistency` flagged HIGH: the MCP object tools bypass secure-field masking. `hype_get_object`, `hype_get_stack_document`, and the full-document/full-part resources serialize whole `Part`/`HypeDocument` Codable values via `codableJSONValue` (Sources/HypeCore/MCP/HypeMCPDocumentBackend.swift:679-685) with no masking — a `.field` part with `fieldStyle == .secure` returns plaintext `textContent`, while the curated AI/HypeTalk surfaces mask it as `(masked)` (HypeToolExecutor.swift:3778-3783, 6277-6283, 760; Interpreter.swift:5768-5773). The channel is HypeDebugServer (local Unix socket, 0700 dir), auto-started at every app launch; external MCP-connected AI automation — exactly the client class the masking defends against — operates through it.

## What Changes

- A private masked-copy transform (`maskedForTransport` for `Part` and `HypeDocument`) applied at every part-bearing MCP serialization site before `codableJSONValue`. Transport copies only — no model/Codable changes, stored document untouched.
- Round-trip guard in `hype_replace_part`: when the stored part is a secure field and the supplied JSON carries the `(masked)` sentinel as `textContent`, the stored secret is preserved instead of being overwritten; response reports `preservedSecureText: true`.
- Explicit ruling: `hype_replace_part` remains a field-level-unvalidated power tool (structural guards retained); stated in its tool description.
- Tool descriptions for `hype_get_stack_document`, `hype_get_object`, `hype_replace_part` and the `/document` resource description updated to disclose masking and replace semantics.
- New `Tests/HypeCoreTests/MCPMaskingTests.swift` covering every masked path, the replace round-trip guard, non-secure passthrough, and a seeded property-style leak sweep.

## Capabilities

### New Capabilities

- `mcp-masking` — secure-field confidentiality contract for the MCP object/document read surface (specs/mcp-masking/spec.md).

### Modified Capabilities

- none.

## Impact

- `Sources/HypeCore/MCP/HypeMCPDocumentBackend.swift` — two private helpers + one constant; five serialization sites wrapped (lines 109, 489, 515, 570, and the replacePart echo at 600); sentinel-preserve guard in `replacePart` (576-603); one resource description (line 68).
- `Sources/HypeCore/MCP/HypeMCPToolBridge.swift` — three tool description strings (lines 95, 100, 172).
- New `Tests/HypeCoreTests/MCPMaskingTests.swift`.
- No changes to models, Codable conformances, HypeToolExecutor, Interpreter, or any other file. `SecurityRegressionTests.swift` and `ScriptStorageGateIntegrationTests.swift` are untouched (the sibling change `control-property-consistency` modifies them in the main tree).
